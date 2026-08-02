using System;
using System.IO;

namespace CameraStream.Windows.Services
{
    public static class LogService
    {
        private static readonly string LogPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CameraStream",
            "streaming.log");

        private static readonly object Lock = new();

        public static void Write(string message)
        {
            try
            {
                var dir = Path.GetDirectoryName(LogPath);
                if (!string.IsNullOrEmpty(dir))
                    Directory.CreateDirectory(dir);

                var entry = $"{DateTime.UtcNow:O} {message}{Environment.NewLine}";
                lock (Lock)
                    File.AppendAllText(LogPath, entry);
            }
            catch
            {
                // Logging must not crash the app.
            }
        }
    }
}
