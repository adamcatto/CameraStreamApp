using System;
using System.ComponentModel;
using System.Windows;
using CameraStream.Windows.ViewModels;

namespace CameraStream.Windows
{
    public partial class MainWindow : Window
    {
        private WindowStyle _savedStyle;
        private WindowState _savedState;
        private ResizeMode _savedResizeMode;
        private bool _isFullScreen;

        public MainWindow()
        {
            InitializeComponent();
            var viewModel = new MainViewModel();
            viewModel.FullScreenToggleRequested += (_, _) => ToggleFullScreen();
            DataContext = viewModel;
        }

        private void ToggleFullScreen()
        {
            if (_isFullScreen)
            {
                WindowStyle = _savedStyle;
                ResizeMode = _savedResizeMode;
                WindowState = _savedState;
                _isFullScreen = false;
            }
            else
            {
                _savedStyle = WindowStyle;
                _savedState = WindowState;
                _savedResizeMode = ResizeMode;
                WindowStyle = WindowStyle.None;
                ResizeMode = ResizeMode.NoResize;
                // Force a state change so a window that is already maximized still
                // redraws without its border/title bar.
                WindowState = WindowState.Normal;
                WindowState = WindowState.Maximized;
                _isFullScreen = true;
            }
        }

        protected override void OnClosing(CancelEventArgs e)
        {
            base.OnClosing(e);
            (DataContext as IDisposable)?.Dispose();
        }
    }
}
