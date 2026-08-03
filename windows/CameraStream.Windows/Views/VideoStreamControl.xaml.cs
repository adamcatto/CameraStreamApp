using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using LibVLCSharp.Shared;
using CameraStream.Windows.Services;
using CameraStream.Windows.ViewModels;

namespace CameraStream.Windows.Views
{
    public partial class VideoStreamControl : UserControl
    {
        private MediaPlayer? _mediaPlayer;
        private Media? _media;
        private DispatcherTimer? _retryTimer;
        private int _retryCount;
        private StreamPlayerViewModel? _viewModel;

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

            _viewModel = vm;
            StartPlayback(resetRetries: true);
        }

        private void StartPlayback(bool resetRetries)
        {
            if (_viewModel == null || App.VlcService == null)
                return;

            StopRetryTimer();
            _mediaPlayer?.Stop();
            _media?.Dispose();

            _mediaPlayer ??= new MediaPlayer(App.VlcService.LibVLC);
            VideoView.MediaPlayer = _mediaPlayer;

            var vm = _viewModel;
            _media = new Media(App.VlcService.LibVLC, $"tcp/h264://{vm.Host}:{vm.Port}", FromType.FromLocation);
            _media.AddOption(":network-caching=150");

            _mediaPlayer.Play(_media);

            if (vm.Host != "127.0.0.1")
                return;

            if (resetRetries)
                _retryCount = 0;

            _retryTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            _retryTimer.Tick += (_, _) =>
            {
                _retryCount++;
                if (_retryCount > 8)
                {
                    StopRetryTimer();
                    return;
                }

                LogService.Write($"[player {vm.Port}] retrying tunneled stream");
                StartPlayback(resetRetries: false);
            };
            _retryTimer.Start();
        }

        private void StopRetryTimer()
        {
            if (_retryTimer == null)
                return;

            _retryTimer.Stop();
            _retryTimer = null;
        }

        private void UserControl_Unloaded(object sender, RoutedEventArgs e)
        {
            StopRetryTimer();
            _viewModel = null;

            _mediaPlayer?.Stop();

            _media?.Dispose();
            _media = null;

            VideoView.MediaPlayer = null;

            _mediaPlayer?.Dispose();
            _mediaPlayer = null;
        }
    }
}
