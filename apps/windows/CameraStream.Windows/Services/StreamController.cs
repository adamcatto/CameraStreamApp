using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using CameraStream.Windows.Models;
using CameraStream.Windows.ViewModels;

namespace CameraStream.Windows.Services
{
    public class StreamController : INotifyPropertyChanged, IDisposable
    {
        private readonly SshService _ssh;
        private readonly Dispatcher _dispatcher;

        private CancellationTokenSource? _cts;
        private CameraWorkspace? _activeWorkspace;
        private string? _credentialFile;
        private readonly List<Process> _tunnels = new();
        private readonly Dictionary<Guid, int> _cameraSshPorts = new();
        private readonly Dictionary<Guid, CameraSettings> _cameraSettings = new();

        private bool _isStreaming;
        private string _status = "Ready";

        public bool IsStreaming
        {
            get => _isStreaming;
            private set => SetProperty(ref _isStreaming, value);
        }

        public string Status
        {
            get => _status;
            private set => SetProperty(ref _status, value);
        }

        public ObservableCollection<StreamPlayerViewModel> StreamPlayers { get; } = new();

        public event PropertyChangedEventHandler? PropertyChanged;

        public StreamController(SshService ssh)
        {
            _ssh = ssh;
            _dispatcher = Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;
        }

        public async void Start(CameraWorkspace workspace)
        {
            if (workspace.Cameras.Count == 0)
                return;

            await StopAsync();
            _cts = new CancellationTokenSource();
            _activeWorkspace = workspace;
            _cameraSettings.Clear();
            foreach (var camera in workspace.Cameras)
                _cameraSettings[camera.Id] = (camera.Settings ?? CameraSettings.Default).Clamped();
            var sessionCredentials = GetCredentials(workspace);
            _credentialFile = AskpassHelper.CreateCredentialsFile(sessionCredentials);
            LogService.Write($"[credentials] loaded {sessionCredentials.Count} accounts for this session");
            if (!string.IsNullOrEmpty(workspace.JumpHost))
            {
                var hasJump = sessionCredentials.ContainsKey(workspace.JumpHost);
                LogService.Write($"[credentials] jump host {workspace.JumpHost} present={hasJump}");
            }

            LogService.Write($"[ssh] using {_ssh.SshPath ?? "missing"} with askpass {_ssh.AskpassPath ?? "missing"}");

            await _dispatcher.InvokeAsync(() =>
            {
                IsStreaming = true;
                Status = $"Starting {workspace.Cameras.Count} camera streams...";
                StreamPlayers.Clear();
            });

            _ = Task.Run(async () =>
            {
                try
                {
                    var usesJumpHost = !string.IsNullOrEmpty(workspace.JumpHost);
                    var launchSuccessCount = 0;
                    var reachableCameras = new List<JumpCamera>();
                    var streamingCameras = new List<JumpCamera>();

                    if (usesJumpHost)
                    {
                        await SetStatusAsync($"Connecting to jump host {workspace.JumpHost}...");
                        LogService.Write($"[jump {workspace.JumpHost}] establishing authenticated SSH connection");
                        var jumpExitCode = await _ssh.ProbeJumpHostAsync(
                            workspace.JumpHost!,
                            _credentialFile,
                            msg => LogService.Write($"[jump {workspace.JumpHost}] {msg}"),
                            _cts.Token);

                        if (jumpExitCode != 0)
                        {
                            await SetFailedStatusAsync($"Error: could not authenticate to jump host {workspace.JumpHost}");
                            return;
                        }

                        LogService.Write($"[jump {workspace.JumpHost}] authenticated SSH connection established");
                        reachableCameras = await OpenJumpHostTunnelsAsync(workspace, _cts.Token);
                        if (reachableCameras.Count == 0)
                        {
                            await SetFailedStatusAsync("Error: jump host connected, but no cameras accepted SSH connections");
                            return;
                        }

                        LogService.Write($"[camera ssh] {reachableCameras.Count}/{workspace.Cameras.Count} cameras connected through jump host");
                    }

                    var camerasToLaunch = usesJumpHost
                        ? reachableCameras
                        : workspace.Cameras.Select((camera, index) => new JumpCamera(camera, index, 0, 0)).ToList();

                    for (int position = 0; position < camerasToLaunch.Count; position++)
                    {
                        if (_cts.IsCancellationRequested)
                            return;

                        var item = camerasToLaunch[position];
                        if (usesJumpHost)
                        {
                            await SetStatusAsync($"Starting reachable camera {position + 1}/{camerasToLaunch.Count}...");
                            var exitCode = await LaunchAndWaitAsync(item.Camera, item.Index, item.LocalSshPort, _cts.Token);
                            if (exitCode == 0)
                            {
                                launchSuccessCount++;
                                streamingCameras.Add(item);
                            }
                            else
                            {
                                LogService.Write($"[launch {item.Camera.Address}] failed with exit code {exitCode}");
                            }

                            await Task.Delay(800, _cts.Token);
                        }
                        else
                        {
                            Launch(item.Camera, item.Index, null);
                        }
                    }

                    await Task.Delay(usesJumpHost ? 5000 : 3000, _cts.Token);

                    if (_cts.IsCancellationRequested)
                        return;

                    if (usesJumpHost)
                    {
                        if (launchSuccessCount == 0)
                        {
                            LogService.Write("[launch] no camera encoders reported a successful start");
                            await SetFailedStatusAsync("Error: cameras connected by SSH, but no encoders started");
                            return;
                        }

                        await Task.Delay(1000, _cts.Token);

                        await _dispatcher.InvokeAsync(() =>
                        {
                            StreamPlayers.Clear();
                            foreach (var item in streamingCameras)
                            {
                                StreamPlayers.Add(CreatePlayer(
                                    item.Camera.Id,
                                    item.Camera.Name,
                                    "127.0.0.1",
                                    item.LocalStreamPort));
                            }
                        });

                        await _dispatcher.InvokeAsync(() =>
                            Status = $"Streaming {launchSuccessCount}/{workspace.Cameras.Count} cameras via {workspace.JumpHost}");
                    }
                    else
                    {
                        await _dispatcher.InvokeAsync(() =>
                        {
                            StreamPlayers.Clear();
                            for (int i = 0; i < workspace.Cameras.Count; i++)
                            {
                                var camera = workspace.Cameras[i];
                                StreamPlayers.Add(CreatePlayer(camera.Id, camera.Name, camera.Host, 8888 + i));
                            }
                        });

                        await _dispatcher.InvokeAsync(() => Status = $"Streaming {workspace.Cameras.Count} cameras");
                    }

                    if (!_cts.IsCancellationRequested)
                    {
                        _ = Task.Run(async () =>
                        {
                            try
                            {
                                await ResolveCameraNamesAsync(
                                    usesJumpHost ? streamingCameras.Select(item => item.Camera).ToList() : workspace.Cameras,
                                    workspace.JumpHost,
                                    usesJumpHost,
                                    _cts.Token);
                            }
                            catch (OperationCanceledException)
                            {
                            }
                        }, _cts.Token);
                    }
                }
                catch (OperationCanceledException)
                {
                }
                catch (Exception ex)
                {
                    LogService.Write($"[stream] {ex}");
                    await SetFailedStatusAsync($"Error: {ex.Message}");
                }
            });
        }

        public async void Stop()
        {
            await StopAsync();
        }

        private async Task StopAsync()
        {
            _cts?.Cancel();

            var workspace = _activeWorkspace;
            var closingCredentialFile = _credentialFile;
            var closingSshPorts = new Dictionary<Guid, int>(_cameraSshPorts);
            var closingTunnels = _tunnels.ToList();
            _activeWorkspace = null;
            _credentialFile = null;
            _cameraSshPorts.Clear();
            _cameraSettings.Clear();
            _tunnels.Clear();

            await _dispatcher.InvokeAsync(() =>
            {
                IsStreaming = false;
                StreamPlayers.Clear();
                Status = "Stopping camera encoders...";
            });

            if (workspace != null)
            {
                var stopTasks = workspace.Cameras.Select(async camera =>
                {
                    try
                    {
                        const string stopCommand = "pkill -x libcamera-vid 2>/dev/null; pkill -x rpicam-vid 2>/dev/null; pkill -x raspivid 2>/dev/null; true";
                        if (!string.IsNullOrEmpty(workspace.JumpHost))
                        {
                            if (closingSshPorts.TryGetValue(camera.Id, out var localSshPort))
                            {
                                await _ssh.RunCommandThroughTunnelAsync(
                                    camera,
                                    localSshPort,
                                    closingCredentialFile,
                                    stopCommand,
                                    msg => LogService.Write($"[stop {camera.Address}] {msg}"),
                                    CancellationToken.None);
                            }
                        }
                        else
                        {
                            await _ssh.RunCommandAsync(
                                camera,
                                null,
                                closingCredentialFile,
                                stopCommand,
                                msg => LogService.Write($"[stop {camera.Address}] {msg}"),
                                CancellationToken.None);
                        }
                    }
                    catch (Exception ex)
                    {
                        LogService.Write($"[stop {camera.Address}] {ex.Message}");
                    }
                });

                await Task.WhenAll(stopTasks);
            }

            foreach (var process in closingTunnels)
            {
                try
                {
                    if (!process.HasExited)
                    {
                        process.Kill();
                        process.WaitForExit(2000);
                    }
                }
                catch
                {
                }
                finally
                {
                    process.Dispose();
                }
            }

            await _dispatcher.InvokeAsync(() => Status = "Stopped");

            if (!string.IsNullOrEmpty(closingCredentialFile))
            {
                _ = Task.Run(async () =>
                {
                    await Task.Delay(8000);
                    AskpassHelper.DeleteCredentialsFile(closingCredentialFile);
                });
            }
        }

        private void Launch(CameraEndpoint camera, int index, string? jumpHost)
        {
            _ssh.StartLaunch(camera, jumpHost, _credentialFile, BuildLaunchCommand(index, GetSettings(camera.Id)),
                msg => LogService.Write($"[launch {camera.Address}] {msg}"));
        }

        private async Task<int> LaunchAndWaitAsync(CameraEndpoint camera, int index, int localSshPort, CancellationToken ct)
        {
            var command = BuildLaunchCommand(index, GetSettings(camera.Id));
            return await _ssh.RunCommandThroughTunnelAsync(camera, localSshPort, _credentialFile, command,
                msg => LogService.Write($"[launch {camera.Address}] {msg}"), ct);
        }

        private CameraSettings GetSettings(Guid id) =>
            _cameraSettings.TryGetValue(id, out var settings) ? settings : CameraSettings.Default;

        private StreamPlayerViewModel CreatePlayer(Guid id, string name, string host, int port) =>
            new StreamPlayerViewModel(id, name, host, port, GetSettings(id).Clone(),
                settings => ApplySettingsAsync(id, settings));

        // Relaunch a single camera's encoder with new capture settings and ask
        // its player to reconnect. The Pi camera stack has no live control
        // channel, so this restarts only that camera's encoder.
        private async Task ApplySettingsAsync(Guid cameraId, CameraSettings settings)
        {
            var workspace = _activeWorkspace;
            var cts = _cts;
            if (workspace == null || cts == null)
                return;

            var index = -1;
            for (int i = 0; i < workspace.Cameras.Count; i++)
            {
                if (workspace.Cameras[i].Id == cameraId)
                {
                    index = i;
                    break;
                }
            }

            if (index < 0)
                return;

            var camera = workspace.Cameras[index];
            var sanitized = settings.Clamped();
            _cameraSettings[cameraId] = sanitized;
            var command = BuildLaunchCommand(index, sanitized);

            await SetStatusAsync($"Applying capture settings to {camera.Name}...");

            try
            {
                if (!string.IsNullOrEmpty(workspace.JumpHost) && _cameraSshPorts.TryGetValue(cameraId, out var localSshPort))
                {
                    await _ssh.RunCommandThroughTunnelAsync(camera, localSshPort, _credentialFile, command,
                        msg => LogService.Write($"[settings {camera.Address}] {msg}"), cts.Token);
                }
                else
                {
                    await _ssh.RunCommandAsync(camera, null, _credentialFile, command,
                        msg => LogService.Write($"[settings {camera.Address}] {msg}"), cts.Token);
                }
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception ex)
            {
                LogService.Write($"[settings {camera.Address}] {ex.Message}");
            }

            // Give the relaunched encoder a moment to start listening before the
            // player reconnects to it.
            try
            {
                await Task.Delay(2500, cts.Token);
            }
            catch (OperationCanceledException)
            {
                return;
            }

            await _dispatcher.InvokeAsync(() =>
            {
                var player = StreamPlayers.FirstOrDefault(p => p.Id == cameraId);
                player?.RequestReload();
                Status = $"Applied capture settings to {camera.Name}";
            });
        }

        private static string BuildLaunchCommand(int index, CameraSettings settings)
        {
            var port = 8888 + index;
            return $"pkill -x libcamera-vid 2>/dev/null || true; " +
                   $"pkill -x rpicam-vid 2>/dev/null || true; " +
                   $"pkill -x raspivid 2>/dev/null || true; " +
                   "if command -v rpicam-vid >/dev/null 2>&1; then c=$(command -v rpicam-vid); " +
                   "elif command -v libcamera-vid >/dev/null 2>&1; then c=$(command -v libcamera-vid); " +
                   "elif command -v raspivid >/dev/null 2>&1; then c=$(command -v raspivid); " +
                   "else exit 127; fi; " +
                   $"if [ \"${{c##*/}}\" = raspivid ]; then nohup \"$c\" {settings.RaspividArguments()} -o tcp://0.0.0.0:{port} -t 0 >/tmp/camera-stream.log 2>&1 & " +
                   $"else nohup \"$c\" {settings.LibcameraArguments()} -o tcp://0.0.0.0:{port} -t 0 >/tmp/camera-stream.log 2>&1 & fi; true";
        }

        private async Task<List<JumpCamera>> OpenJumpHostTunnelsAsync(CameraWorkspace workspace, CancellationToken ct)
        {
            var jumpHost = workspace.JumpHost!;
            var reachable = new List<JumpCamera>();

            for (int i = 0; i < workspace.Cameras.Count; i++)
            {
                ct.ThrowIfCancellationRequested();

                var camera = workspace.Cameras[i];
                var remotePort = 8888 + i;
                var localPort = 18000 + i;
                var localSshPort = 19000 + i;

                await SetStatusAsync($"Checking camera SSH {i + 1}/{workspace.Cameras.Count} ({camera.Address})...");

                var process = _ssh.StartTunnel(camera, remotePort, localPort, localSshPort, jumpHost, _credentialFile,
                    msg => LogService.Write($"[tunnel {camera.Address}] {msg}"));

                _tunnels.Add(process);

                if (await WaitForLocalListenersAsync(new[] { localPort, localSshPort }, process, TimeSpan.FromSeconds(8), ct))
                {
                    var probeExitCode = await _ssh.RunCommandThroughTunnelAsync(
                        camera,
                        localSshPort,
                        _credentialFile,
                        "printf '__CAMERA_STREAM_CAMERA_READY__\\n'",
                        msg => LogService.Write($"[camera ssh {camera.Address}] {msg}"),
                        ct);

                    if (probeExitCode == 0)
                    {
                        LogService.Write($"[camera ssh {camera.Address}] authenticated connection established via {jumpHost}");
                        _cameraSshPorts[camera.Id] = localSshPort;
                        reachable.Add(new JumpCamera(camera, i, localSshPort, localPort));
                    }
                    else
                    {
                        LogService.Write($"[camera ssh {camera.Address}] unavailable; continuing with remaining cameras");
                        StopTunnel(process);
                    }
                }
                else
                {
                    LogService.Write($"[tunnel {camera.Address}] failed to establish local forwards; continuing");
                    StopTunnel(process);
                }

                await Task.Delay(400, ct);
            }

            return reachable;
        }

        private void StopTunnel(Process process)
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill();
                    process.WaitForExit(2000);
                }
            }
            catch
            {
            }

            _tunnels.Remove(process);
            process.Dispose();
        }

        private static bool IsLocalPortListening(int port)
        {
            return IPGlobalProperties.GetIPGlobalProperties()
                .GetActiveTcpListeners()
                .Any(endpoint => endpoint.Port == port &&
                    (IPAddress.IsLoopback(endpoint.Address) || endpoint.Address.Equals(IPAddress.Any)));
        }

        private static async Task<bool> WaitForLocalListenersAsync(
            IReadOnlyCollection<int> ports,
            Process tunnel,
            TimeSpan timeout,
            CancellationToken ct)
        {
            var deadline = DateTime.UtcNow + timeout;

            while (DateTime.UtcNow < deadline)
            {
                ct.ThrowIfCancellationRequested();

                if (tunnel.HasExited)
                {
                    LogService.Write($"[tunnel] session exited early with status {tunnel.ExitCode}");
                    return false;
                }

                if (ports.All(IsLocalPortListening))
                    return true;

                await Task.Delay(200, ct);
            }

            return false;
        }

        private async Task ResolveCameraNamesAsync(
            List<CameraEndpoint> cameras,
            string? jumpHost,
            bool serializeJumpHostLookups,
            CancellationToken ct)
        {
            if (serializeJumpHostLookups)
            {
                foreach (var camera in cameras)
                {
                    await ResolveCameraNameAsync(camera, jumpHost, ct);
                    await Task.Delay(300, ct);
                }

                return;
            }

            var tasks = cameras.Select(camera => ResolveCameraNameAsync(camera, jumpHost, ct));
            await Task.WhenAll(tasks);
        }

        private async Task ResolveCameraNameAsync(CameraEndpoint camera, string? jumpHost, CancellationToken ct)
        {
            string? name;
            if (!string.IsNullOrEmpty(jumpHost) && _cameraSshPorts.TryGetValue(camera.Id, out var localSshPort))
                name = await _ssh.GetCameraNameThroughTunnelAsync(camera, localSshPort, _credentialFile, ct);
            else
                name = await _ssh.GetCameraNameAsync(camera, jumpHost, _credentialFile, ct);
            if (string.IsNullOrWhiteSpace(name))
                return;

            await _dispatcher.InvokeAsync(() =>
            {
                var player = StreamPlayers.FirstOrDefault(p => p.Id == camera.Id);
                if (player != null)
                    player.Name = name.Trim();
            });
        }

        private Dictionary<string, string> GetCredentials(CameraWorkspace workspace)
        {
            var dict = new Dictionary<string, string>();

            foreach (var camera in workspace.Cameras)
            {
                if (CredentialStore.Instance.Passwords.TryGetValue(camera.CredentialAccount, out var pw) && !string.IsNullOrEmpty(pw))
                    dict[camera.CredentialAccount] = pw;
            }

            if (!string.IsNullOrEmpty(workspace.JumpHost)
                && CredentialStore.Instance.Passwords.TryGetValue(workspace.JumpHost, out var jpw)
                && !string.IsNullOrEmpty(jpw))
            {
                dict[workspace.JumpHost] = jpw;
            }

            return dict;
        }

        private async Task SetStatusAsync(string status)
        {
            await _dispatcher.InvokeAsync(() => Status = status);
        }

        private async Task SetFailedStatusAsync(string status)
        {
            await _dispatcher.InvokeAsync(() =>
            {
                Status = status;
                IsStreaming = false;
                StreamPlayers.Clear();
            });
        }

        private readonly record struct JumpCamera(
            CameraEndpoint Camera,
            int Index,
            int LocalSshPort,
            int LocalStreamPort);

        private void SetProperty<T>(ref T field, T value, [CallerMemberName] string propertyName = "")
        {
            if (EqualityComparer<T>.Default.Equals(field, value))
                return;

            field = value;
            _dispatcher.Invoke(() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName)));
        }

        public void Dispose() => Stop();
    }
}
