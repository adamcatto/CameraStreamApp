using System.Windows;
using CameraStream.Windows.Services;
using LibVLCSharp.Shared;

namespace CameraStream.Windows
{
    public partial class App : Application
    {
        public static VlcService VlcService { get; } = new VlcService();

        protected override void OnStartup(StartupEventArgs e)
        {
            LogService.Write("Camera Stream starting...");
            Core.Initialize();
            base.OnStartup(e);
            LogService.Write("Camera Stream UI loaded.");
        }

        protected override void OnExit(ExitEventArgs e)
        {
            VlcService.Dispose();
            base.OnExit(e);
        }
    }
}
