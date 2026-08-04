using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using CameraStream.Windows.Models;

namespace CameraStream.Windows.Services
{
    public static class ClusterShellService
    {
        public static string? Open(CameraWorkspace workspace, SshService ssh)
        {
            if (workspace.Cameras.Count == 0)
                return "Add at least one camera to open a cluster shell.";

            var username = workspace.Cameras.First().Username;
            var hosts = workspace.Cameras.Select(c => c.Host).ToList();

            if (!IsSafeIdentifier(username))
                return "The camera username contains unsupported characters.";

            if (hosts.Any(h => !IsSafeHost(h)))
                return "One or more camera hosts contain unsupported characters.";

            var sshPath = ssh.SshPath ?? "ssh";
            var wt = FindWt();

            if (wt != null)
            {
                var args = BuildWtArgs(sshPath, username, hosts);
                try
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = wt,
                        Arguments = args,
                        UseShellExecute = true
                    };
                    Process.Start(psi);
                    return null;
                }
                catch (Exception ex)
                {
                    return $"Could not open Windows Terminal: {ex.Message}";
                }
            }

            // Fallback: open each camera in a separate command window.
            foreach (var h in hosts)
            {
                try
                {
                    var sshArg = sshPath.Contains(' ') ? $"\"{sshPath}\"" : sshPath;
                    var psi = new ProcessStartInfo("cmd", $"/c start \"\" {sshArg} {username}@{h}")
                    {
                        UseShellExecute = true
                    };
                    Process.Start(psi);
                }
                catch (Exception ex)
                {
                    return ex.Message;
                }
            }

            return null;
        }

        private static string? FindWt()
        {
            var candidates = new List<string>
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps", "wt.exe")
            };

            var pathEnv = Environment.GetEnvironmentVariable("PATH");
            if (!string.IsNullOrEmpty(pathEnv))
            {
                foreach (var dir in pathEnv.Split(Path.PathSeparator))
                {
                    candidates.Add(Path.Combine(dir.Trim(), "wt.exe"));
                }
            }

            foreach (var c in candidates)
            {
                try
                {
                    if (File.Exists(c))
                        return c;
                }
                catch
                {
                }
            }

            return null;
        }

        private static string BuildWtArgs(string sshPath, string username, List<string> hosts)
        {
            var sb = new StringBuilder();
            bool first = true;

            foreach (var h in hosts)
            {
                if (!first)
                    sb.Append(" ; ");

                first = false;

                var sshArg = sshPath.Contains(' ') ? $"\"{sshPath}\"" : sshPath;
                sb.Append($"new-tab {sshArg} {username}@{h}");
            }

            return sb.ToString();
        }

        private static bool IsSafeIdentifier(string value)
            => !string.IsNullOrEmpty(value) && Regex.IsMatch(value, @"^[A-Za-z0-9._-]+$");

        private static bool IsSafeHost(string value)
            => !string.IsNullOrEmpty(value) && Regex.IsMatch(value, @"^[A-Za-z0-9._:-]+$");
    }
}
