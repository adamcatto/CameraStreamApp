using System;
using System.ComponentModel;
using System.Windows;
using CameraStream.Windows.ViewModels;

namespace CameraStream.Windows
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
            DataContext = new MainViewModel();
        }

        protected override void OnClosing(CancelEventArgs e)
        {
            base.OnClosing(e);
            (DataContext as IDisposable)?.Dispose();
        }
    }
}
