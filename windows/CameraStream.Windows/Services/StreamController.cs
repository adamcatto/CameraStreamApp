using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Net.Sockets;
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

            Stop();
            _cts = new CancellationTokenSource();
            _activeWorkspace = workspace;
            _credentialFile = AskpassHelper.CreateCredentialsFile(GetCredentials(workspace));

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
                    for (int i = 0; i < workspace.Cameras.Count; i++)
                    {
                        if (_cts.IsCancellationRequested)
                            return;

                        Launch(workspace.Cameras[i], i, workspace.JumpHost);

                        if (usesJumpHost)
                            await Task.Delay(350, _cts.Token);
                    }

                    await Task.Delay(3000, _cts.Token);

                    if (_cts.IsCancellationRequested)
                        return;

                    if (usesJumpHost)
                    {
                        var forwards = workspace.Cameras
                            .Select((camera, index) => (camera, 8888 + index, 18000 + index))
                            .ToList();

                        OpenJumpHostTunnels(forwards, workspace.JumpHost!);

                        var ready = await WaitForLocalPortAsync("127.0.0.1", 18000, TimeSpan.FromSeconds(20), _cts.Token);
                        if (!ready)
                            LogService.Write("[tunnel] timed out waiting for local port 18000");

                        await Task.Delay(500, _cts.Token);

                        await _dispatcher.InvokeAsync(() =>
                        {
                            StreamPlayers.Clear();
                            for (int i = 0; i < workspace.Cameras.Count; i++)
                            {
                                var camera = workspace.Cameras[i];
                                StreamPlayers.Add(new StreamPlayerViewModel(camera.Id, camera.Name, "127.0.0.1", 18000 + i));
                            }
                        });
                    }
                    else
                    {
                        await _dispatcher.InvokeAsync(() =>
                        {
                            StreamPlayers.Clear();
                            for (int i = 0; i < workspace.Cameras.Count; i++)
                            {
                                var camera = workspace.Cameras[i];
                                StreamPlayers.Add(new StreamPlayerViewModel(camera.Id, camera.Name, camera.Host, 8888 + i));
                            }
                        });
                    }

                    if (!_cts.IsCancellationRequested)
                        await ResolveCameraNamesAsync(workspace.Cameras, workspace.JumpHost, usesJumpHost, _cts.Token);

                    await _dispatcher.InvokeAsync(() => Status = $"Streaming {workspace.Cameras.Count} cameras");
                }
                catch (OperationCanceledException)
                {
                }
                catch (Exception ex)
                {
                    await SetStatusAsync($"Error: {ex.Message}");
                }
            });
        }

        public async void Stop()
        {
            _cts?.Cancel();

            var workspace = _activeWorkspace;
            var closingCredentialFile = _credentialFile;
            _activeWorkspace = null;
            _credentialFile = null;

            // Kill tunnels synchronously so app exit cleans up immediately.
            foreach (var p in _tunnels.ToList())
            {
                try
                {
                    p.Kill();
                }
                catch
                {
                }
                finally
                {
                    try
                    {
                        p.Dispose();
                    }
                    catch
                    {
                    }
                }
            }

            _tunnels.Clear();

            await _dispatcher.InvokeAsync(() =>
            {
                IsStreaming = false;
                StreamPlayers.Clear();
                Status = "Stopping camera encoders...";
            });

            if (workspace != null)
            {
                foreach (var camera in workspace.Cameras)
                {
                    try
                    {
                        await _ssh.RunCommandAsync(camera, workspace.JumpHost, closingCredentialFile,
                            "pkill -x libcamera-vid 2>/dev/null; pkill -x rpicam-vid 2>/dev/null; pkill -x raspivid 2>/dev/null; true",
                            msg => LogService.Write($"[stop {camera.Address}] {msg}"),
                            CancellationToken.None);
                    }
                    catch (Exception ex)
                    {
                        LogService.Write($"[stop {camera.Address}] {ex.Message}");
                    }
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
            var port = 8888 + index;
            var command = $"pkill -x libcamera-vid 2>/dev/null || true; " +
                          $"pkill -x rpicam-vid 2>/dev/null || true; " +
                          $"pkill -x raspivid 2>/dev/null || true; " +
                          "if command -v rpicam-vid >/dev/null 2>&1; then c=$(command -v rpicam-vid); " +
                          "elif command -v libcamera-vid >/dev/null 2>&1; then c=$(command -v libcamera-vid); " +
                          "elif command -v raspivid >/dev/null 2>&1; then c=$(command -v raspivid); " +
                          "else exit 127; fi; " +
                          $"if [ \"${{c##*/}}\" = raspivid ]; then nohup \"$c\" -md 4 -ss 20000 -ISO 32 -w 1640 -h 1232 -fps 30 -ih -n -l -o tcp://0.0.0.0:{port} -t 0 >/tmp/camera-stream.log 2>&1 & " +
                          $"else nohup \"$c\" --shutter 20000 --gain 32 --brightness 0.2 --width 1920 --height 1080 --codec h264 --framerate 30 --autofocus-mode auto --lens-position 3 --inline --listen -o tcp://0.0.0.0:{port} -t 0 >/tmp/camera-stream.log 2>&1 & fi";

            _ssh.StartLaunch(camera, jumpHost, _credentialFile, command,
                msg => LogService.Write($"[launch {camera.Address}] {msg}"));
        }

        private void OpenJumpHostTunnels(
            IReadOnlyList<(CameraEndpoint camera, int remotePort, int localPort)> forwards,
            string jumpHost)
        {
            var process = _ssh.StartJumpHostTunnels(forwards, jumpHost, _credentialFile,
                msg => LogService.Write($"[tunnel] {msg}"));

            _tunnels.Add(process);
        }

        private static async Task<bool> WaitForLocalPortAsync(string host, int port, TimeSpan timeout, CancellationToken ct)
        {
            var deadline = DateTime.UtcNow + timeout;

            while (DateTime.UtcNow < deadline)
            {
                ct.ThrowIfCancellationRequested();

                try
                {
                    using var client = new TcpClient();
                    var connectTask = client.ConnectAsync(host, port);
                    var completed = await Task.WhenAny(connectTask, Task.Delay(250, ct));
                    if (completed == connectTask && client.Connected)
                        return true;
                }
                catch
                {
                }

                await Task.Delay(250, ct);
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
            var name = await _ssh.GetCameraNameAsync(camera, jumpHost, _credentialFile, ct);
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
