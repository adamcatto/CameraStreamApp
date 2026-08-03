using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CameraStream.Windows.Models;

namespace CameraStream.Windows.Services
{
    public class SshService
    {
        public string? SshPath { get; }
        public string? AskpassPath { get; }
        public bool IsAvailable => !string.IsNullOrEmpty(SshPath) && !string.IsNullOrEmpty(AskpassPath);

        public SshService()
        {
            SshPath = FindSsh();
            AskpassPath = FindAskpass();
        }

        private static string? FindSsh()
        {
            var candidates = new List<string>
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "OpenSSH", "ssh.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Sysnative", "OpenSSH", "ssh.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Git", "usr", "bin", "ssh.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Git", "usr", "bin", "ssh.exe")
            };

            foreach (var c in candidates)
            {
                if (File.Exists(c))
                    return c;
            }

            var pathEnv = Environment.GetEnvironmentVariable("PATH");
            if (!string.IsNullOrEmpty(pathEnv))
            {
                foreach (var dir in pathEnv.Split(Path.PathSeparator))
                {
                    var p = Path.Combine(dir.Trim(), "ssh.exe");
                    if (File.Exists(p))
                        return p;
                }
            }

            return null;
        }

        private static string? FindAskpass()
        {
            var name = "CameraSSHAskpass.cmd";
            var baseDir = AppContext.BaseDirectory;
            var path = Path.Combine(baseDir, name);
            if (File.Exists(path))
                return path;

            var main = Process.GetCurrentProcess().MainModule?.FileName;
            if (!string.IsNullOrEmpty(main))
            {
                path = Path.Combine(Path.GetDirectoryName(main)!, name);
                if (File.Exists(path))
                    return path;
            }

            return null;
        }

        private void AddCommonOptions(ProcessStartInfo psi)
        {
            psi.ArgumentList.Add("-F");
            psi.ArgumentList.Add("NUL");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("ControlMaster=no");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("ControlPersist=no");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("ConnectTimeout=6");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("StrictHostKeyChecking=accept-new");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("PubkeyAuthentication=no");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("PreferredAuthentications=password");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("PasswordAuthentication=yes");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("KbdInteractiveAuthentication=yes");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("NumberOfPasswordPrompts=12");
        }

        public Process StartLaunch(CameraEndpoint camera, string? jumpHost, string? credentialFile,
            string command, Action<string>? onLog)
        {
            if (!IsAvailable || SshPath == null)
                throw new InvalidOperationException("SSH not available");

            var psi = BuildProcessStartInfo(camera, jumpHost, command, credentialFile);
            var process = new Process { StartInfo = psi, EnableRaisingEvents = true };

            if (onLog != null)
            {
                process.OutputDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                        onLog(e.Data);
                };
                process.ErrorDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                        onLog(e.Data);
                };
            }

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            return process;
        }

        public async Task<int> RunCommandAsync(CameraEndpoint camera, string? jumpHost, string? credentialFile,
            string command, Action<string>? onLog, CancellationToken ct)
        {
            if (!IsAvailable)
            {
                onLog?.Invoke("SSH not available");
                return 1;
            }

            var psi = BuildProcessStartInfo(camera, jumpHost, command, credentialFile);
            using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };

            if (onLog != null)
            {
                process.OutputDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                        onLog(e.Data);
                };
                process.ErrorDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                        onLog(e.Data);
                };
            }

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            await Task.Run(() => process.WaitForExit(), ct);
            onLog?.Invoke($"exited with status {process.ExitCode}");
            return process.ExitCode;
        }

        public async Task<int> RunCommandViaJumpShellAsync(
            CameraEndpoint camera,
            string jumpHost,
            string? credentialFile,
            string remoteCommand,
            Action<string>? onLog,
            CancellationToken ct)
        {
            if (!IsAvailable || SshPath == null)
            {
                onLog?.Invoke("SSH not available");
                return 1;
            }

            var escaped = remoteCommand.Replace("'", "'\\''");
            var wrapped = $"ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes {camera.Address} '{escaped}'";

            var psi = new ProcessStartInfo(SshPath)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };

            AddCommonOptions(psi);
            psi.ArgumentList.Add(jumpHost);
            psi.ArgumentList.Add(wrapped);

            SetEnvironment(psi, jumpHost, credentialFile);

            using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };

            if (onLog != null)
            {
                process.OutputDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                        onLog(e.Data);
                };
                process.ErrorDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                        onLog(e.Data);
                };
            }

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            await Task.Run(() => process.WaitForExit(), ct);
            onLog?.Invoke($"jump-shell exited with status {process.ExitCode}");
            return process.ExitCode;
        }

        public Process StartTunnel(CameraEndpoint camera, int remotePort, int localPort, string jumpHost,
            string? credentialFile, Action<string>? onLog)
        {
            if (!IsAvailable || SshPath == null)
                throw new InvalidOperationException("SSH not available");

            var psi = new ProcessStartInfo(SshPath)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };

            AddCommonOptions(psi);
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("ServerAliveInterval=30");
            psi.ArgumentList.Add("-o");
            psi.ArgumentList.Add("ServerAliveCountMax=3");
            psi.ArgumentList.Add("-N");
            psi.ArgumentList.Add("-L");
            psi.ArgumentList.Add($"127.0.0.1:{localPort}:{camera.Host}:{remotePort}");
            psi.ArgumentList.Add(jumpHost);

            SetEnvironment(psi, jumpHost, credentialFile);

            var process = new Process { StartInfo = psi, EnableRaisingEvents = true };

            if (onLog != null)
            {
                process.OutputDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                        onLog(e.Data);
                };
                process.ErrorDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                        onLog(e.Data);
                };
                process.Exited += (s, e) =>
                {
                    onLog($"exited with status {process.ExitCode}");
                };
            }

            process.Start();
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();

            return process;
        }

        public async Task<string?> GetCameraNameAsync(CameraEndpoint camera, string? jumpHost,
            string? credentialFile, CancellationToken ct)
        {
            if (!IsAvailable)
                return null;

            var command = "boxid=$(printenv BOXID 2>/dev/null || true); if [ -n \"$boxid\" ]; then printf '%s' \"$boxid\"; else hostname; fi";
            var psi = BuildProcessStartInfo(camera, jumpHost, command, credentialFile);
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = false;

            using var process = new Process { StartInfo = psi };
            process.Start();

            var outputTask = process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync(ct);
            var output = await outputTask;

            return string.IsNullOrWhiteSpace(output) ? null : output.Trim();
        }

        private ProcessStartInfo BuildProcessStartInfo(CameraEndpoint camera, string? jumpHost, string command, string? credentialFile)
        {
            if (SshPath == null)
                throw new InvalidOperationException("SSH not found");

            var psi = new ProcessStartInfo(SshPath)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };

            AddCommonOptions(psi);

            if (!string.IsNullOrEmpty(jumpHost))
            {
                psi.ArgumentList.Add("-J");
                psi.ArgumentList.Add(jumpHost);
            }

            psi.ArgumentList.Add(camera.Address);
            psi.ArgumentList.Add(command);

            SetEnvironment(psi, camera.CredentialAccount, credentialFile);

            return psi;
        }

        private void SetEnvironment(ProcessStartInfo psi, string account, string? credentialFile)
        {
            if (!string.IsNullOrEmpty(AskpassPath))
            {
                psi.Environment["SSH_ASKPASS"] = AskpassPath;
                psi.Environment["SSH_ASKPASS_REQUIRE"] = "force";
            }

            psi.Environment["CAMERA_STREAM_KEYCHAIN_ACCOUNT"] = account;

            if (!string.IsNullOrEmpty(credentialFile))
                psi.Environment["CAMERA_STREAM_CREDENTIALS_FILE"] = credentialFile;
        }
    }
}
