using System;
using System.Windows;
using System.Windows.Threading;
using CameraStream.Windows.Services;

namespace CameraStream.Windows
{
    public partial class App : Application
    {
        public static VlcService VlcService { get; } = new VlcService();

        protected override void OnStartup(StartupEventArgs e)
        {
            LogService.Write("Camera Stream starting...");

            DispatcherUnhandledException += (_, args) =>
            {
                LogService.Write($"Unhandled UI exception: {args.Exception.Message}");
                MessageBox.Show(
                    $"Camera Stream encountered an error:\n\n{args.Exception.Message}",
                    "Camera Stream",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
                args.Handled = true;
            };

            AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            {
                if (args.ExceptionObject is Exception ex)
                    LogService.Write($"Unhandled exception: {ex.Message}");
            };

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
