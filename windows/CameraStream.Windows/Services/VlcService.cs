using System;
using System.IO;
using LibVLCSharp.Shared;

namespace CameraStream.Windows.Services
{
    public class VlcService : IDisposable
    {
        private static bool _coreInitialized;
        private static readonly object InitLock = new();

        private LibVLC? _libVLC;

        public LibVLC LibVLC
        {
            get
            {
                EnsureCoreInitialized();
                return _libVLC ??= new LibVLC();
            }
        }

        public static void EnsureCoreInitialized()
        {
            if (_coreInitialized)
                return;

            lock (InitLock)
            {
                if (_coreInitialized)
                    return;

                var libvlcDir = FindLibVlcDirectory();
                if (libvlcDir != null)
                {
                    LogService.Write($"Initializing LibVLC from {libvlcDir}");
                    Core.Initialize(libvlcDir);
                }
                else
                {
                    LogService.Write("LibVLC directory not found; trying default Core.Initialize()");
                    Core.Initialize();
                }

                _coreInitialized = true;
            }
        }

        private static string? FindLibVlcDirectory()
        {
            var baseDir = AppContext.BaseDirectory;
            var candidates = new[]
            {
                Path.Combine(baseDir, "libvlc", "win-x64"),
                Path.Combine(baseDir, "libvlc", "win-x86"),
                baseDir
            };

            foreach (var dir in candidates)
            {
                if (File.Exists(Path.Combine(dir, "libvlc.dll")))
                    return dir;
            }

            return null;
        }

        public void Dispose()
        {
            _libVLC?.Dispose();
            _libVLC = null;
        }
    }
}
