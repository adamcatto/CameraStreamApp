using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

namespace CameraStream.Windows.Services
{
    public static class BundledTools
    {
        public static string? GetBundledPath(string name)
        {
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

        public static string GetToolStatus(SshService ssh)
        {
            var parts = new List<string>();

            if (!string.IsNullOrEmpty(ssh.SshPath))
                parts.Add($"OpenSSH ({ssh.SshPath})");
            else
                parts.Add("OpenSSH (not found)");

            var askpass = GetBundledPath("CameraSSHAskpass.exe") ?? GetBundledPath("CameraSSHAskpass.cmd");
            if (!string.IsNullOrEmpty(askpass))
                parts.Add($"CameraSSHAskpass ({askpass})");
            else
                parts.Add("CameraSSHAskpass (missing)");

            return string.Join(", ", parts);
        }
    }
}
