using System;
using System.Threading.Tasks;
using CameraStream.Windows.Models;
using CameraStream.Windows.Services;

namespace CameraStream.Windows.ViewModels
{
    public class StreamPlayerViewModel : ObservableObject
    {
        private readonly Func<CameraSettings, Task>? _applyAsync;
        private string _name;
        private bool _settingsOpen;
        private bool _isApplying;

        public Guid Id { get; }

        public string Name
        {
            get => _name;
            set => SetProperty(ref _name, value);
        }

        public string Host { get; }
        public int Port { get; }

        public CameraSettingsViewModel Settings { get; }

        public bool SettingsOpen
        {
            get => _settingsOpen;
            set => SetProperty(ref _settingsOpen, value);
        }

        public bool IsApplying
        {
            get => _isApplying;
            private set
            {
                if (SetProperty(ref _isApplying, value))
                    OnPropertyChanged(nameof(CanApply));
            }
        }

        public bool CanApply => !_isApplying;

        // Raised when the encoder has been relaunched with new settings and the
        // player view should tear down and reconnect its stream.
        public event EventHandler? ReloadRequested;

        public RelayCommand ToggleSettingsCommand { get; }
        public RelayCommand ApplyCommand { get; }
        public RelayCommand ResetCommand { get; }

        public StreamPlayerViewModel(
            Guid id,
            string name,
            string host,
            int port,
            CameraSettings settings,
            Func<CameraSettings, Task>? applyAsync = null)
        {
            Id = id;
            _name = name;
            Host = host;
            Port = port;
            _applyAsync = applyAsync;
            Settings = new CameraSettingsViewModel(settings);
            ToggleSettingsCommand = new RelayCommand(() => SettingsOpen = !SettingsOpen);
            ApplyCommand = new RelayCommand(async () => await ApplyAsync(), () => CanApply);
            ResetCommand = new RelayCommand(() => Settings.CopyFrom(CameraSettings.Default));
        }

        public void RequestReload() => ReloadRequested?.Invoke(this, EventArgs.Empty);

        private async Task ApplyAsync()
        {
            if (_applyAsync == null)
                return;

            IsApplying = true;
            try
            {
                await _applyAsync(Settings.ToModel());
            }
            catch (Exception ex)
            {
                LogService.Write($"[settings {Host}:{Port}] {ex.Message}");
            }
            finally
            {
                IsApplying = false;
            }
        }
    }
}
