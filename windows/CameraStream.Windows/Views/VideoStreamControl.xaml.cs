using System;
using System.Windows;
using System.Windows.Controls;
using LibVLCSharp.Shared;
using CameraStream.Windows.ViewModels;

namespace CameraStream.Windows.Views
{
    public partial class VideoStreamControl : UserControl
    {
        private MediaPlayer? _mediaPlayer;
        private Media? _media;

        public VideoStreamControl()
        {
            InitializeComponent();
        }

        private void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            if (DataContext is not StreamPlayerViewModel vm)
                return;

            if (App.VlcService == null)
                return;

            _mediaPlayer = new MediaPlayer(App.VlcService.LibVLC);
            VideoView.MediaPlayer = _mediaPlayer;

            _media = new Media(App.VlcService.LibVLC, $"tcp/h264://{vm.Host}:{vm.Port}", FromType.FromLocation);
            _media.AddOption(":network-caching=100");

            _mediaPlayer.Play(_media);
        }

        private void UserControl_Unloaded(object sender, RoutedEventArgs e)
        {
            _mediaPlayer?.Stop();

            _media?.Dispose();
            _media = null;

            VideoView.MediaPlayer = null;

            _mediaPlayer?.Dispose();
            _mediaPlayer = null;
        }
    }
}
