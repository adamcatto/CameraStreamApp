using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using LibVLCSharp.Shared;
using CameraStream.Windows.ViewModels;

namespace CameraStream.Windows.Views
{
    public partial class VideoStreamControl : UserControl
    {
        private MediaPlayer? _mediaPlayer;
        private Media? _media;
        private DispatcherTimer? _startTimer;
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
            _viewModel.ReloadRequested += OnReloadRequested;

            // rpicam-vid --listen accepts one TCP client per encoder. Do not connect
            // until tunnels are ready, and never reconnect once playback starts —
            // except on an explicit reload after a capture-settings relaunch.
            if (vm.Host == "127.0.0.1")
            {
                _startTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
                _startTimer.Tick += (_, _) =>
                {
                    StopStartTimer();
                    StartPlaybackOnce();
                };
                _startTimer.Start();
                return;
            }

            StartPlaybackOnce();
        }

        private void StartPlaybackOnce()
        {
            if (_viewModel == null || App.VlcService == null)
                return;

            _mediaPlayer?.Stop();
            _media?.Dispose();

            _mediaPlayer ??= new MediaPlayer(App.VlcService.LibVLC);
            VideoView.MediaPlayer = _mediaPlayer;

            var vm = _viewModel;
            _media = new Media(App.VlcService.LibVLC, $"tcp/h264://{vm.Host}:{vm.Port}", FromType.FromLocation);
            _media.AddOption(":network-caching=150");

            _mediaPlayer.Play(_media);
        }

        private void OnReloadRequested(object? sender, EventArgs e)
        {
            // The encoder was relaunched with new capture settings; reconnect the
            // player to pick up the new stream.
            Dispatcher.Invoke(StartPlaybackOnce);
        }

        private void StopStartTimer()
        {
            if (_startTimer == null)
                return;

            _startTimer.Stop();
            _startTimer = null;
        }

        private void UserControl_Unloaded(object sender, RoutedEventArgs e)
        {
            StopStartTimer();

            if (_viewModel != null)
                _viewModel.ReloadRequested -= OnReloadRequested;
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
