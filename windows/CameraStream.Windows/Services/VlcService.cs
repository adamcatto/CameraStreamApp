using System;
using LibVLCSharp.Shared;

namespace CameraStream.Windows.Services
{
    public class VlcService : IDisposable
    {
        private LibVLC? _libVLC;

        public LibVLC LibVLC => _libVLC ??= new LibVLC();

        public void Dispose()
        {
            _libVLC?.Dispose();
            _libVLC = null;
        }
    }
}
