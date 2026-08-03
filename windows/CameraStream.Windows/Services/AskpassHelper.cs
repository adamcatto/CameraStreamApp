using System;
using System.Collections.Generic;
using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace CameraStream.Windows.Services
{
    public static class AskpassHelper
    {
        public static string? CreateCredentialsFile(Dictionary<string, string> credentials)
        {
            if (credentials.Count == 0)
                return null;

            var path = Path.Combine(Path.GetTempPath(), $"camera-stream-{Guid.NewGuid()}.json");
            var json = JsonSerializer.Serialize(credentials);
            File.WriteAllText(path, json, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

            try
            {
                RestrictToCurrentUser(path);
            }
            catch
            {
                // ACL restrictions are best-effort; the file still lives in the user's temp directory.
            }

            return path;
        }

        public static void DeleteCredentialsFile(string? path)
        {
            if (!string.IsNullOrEmpty(path) && File.Exists(path))
            {
                try
                {
                    File.Delete(path);
                }
                catch
                {
                }
            }
        }

        private static void RestrictToCurrentUser(string path)
        {
            var fileInfo = new FileInfo(path);
            var security = new FileSecurity();

            var user = WindowsIdentity.GetCurrent().User;
            if (user == null)
                return;

            security.AddAccessRule(new FileSystemAccessRule(user, FileSystemRights.Read, AccessControlType.Allow));
            fileInfo.SetAccessControl(security);
        }
    }
}
