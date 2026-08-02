using System.Windows;
using CameraStream.Windows.Services;

namespace CameraStream.Windows
{
    public partial class App : Application
    {
        public static VlcService VlcService { get; } = new VlcService();

        protected override void OnExit(ExitEventArgs e)
        {
            VlcService.Dispose();
            base.OnExit(e);
        }
    }
}
