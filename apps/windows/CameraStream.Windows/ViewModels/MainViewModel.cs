using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using CameraStream.Windows.Models;
using CameraStream.Windows.Services;
using CameraStream.Windows.Views;

namespace CameraStream.Windows.ViewModels
{
    public class MainViewModel : ObservableObject, IDisposable
    {
        private readonly WorkspaceStore _store;
        private readonly SshService _ssh;
        private readonly StreamController _streamer;

        public ObservableCollection<WorkspaceViewModel> Workspaces { get; } = new();

        private WorkspaceViewModel? _selectedWorkspace;
        public WorkspaceViewModel? SelectedWorkspace
        {
            get => _selectedWorkspace;
            set
            {
                if (SetProperty(ref _selectedWorkspace, value))
                {
                    ShowSettings = false;
                    UpdateVisibility();
                    UpdateCommands();
                }
            }
        }

        private bool _showSettings;
        public bool ShowSettings
        {
            get => _showSettings;
            set
            {
                if (SetProperty(ref _showSettings, value))
                {
                    if (value)
                        CredentialStore.Instance.RefreshItems(Workspaces.ToList());

                    UpdateVisibility();
                    UpdateCommands();
                }
            }
        }

        public bool IsStreaming => _streamer.IsStreaming;
        public string Status => _streamer.Status;
        public ObservableCollection<StreamPlayerViewModel> StreamPlayers => _streamer.StreamPlayers;

        // The players shown in the stream area: every player normally, or just the
        // focused one. Returning the live collection when unfocused keeps its
        // add/remove notifications flowing to the grid; a single-item array while
        // focused ensures only that one camera keeps a live connection.
        public IEnumerable<StreamPlayerViewModel> DisplayedPlayers =>
            FocusedPlayer is { } focused ? new[] { focused } : StreamPlayers;

        public CredentialStore CredentialStore => CredentialStore.Instance;
        public string BundledToolsStatus => BundledTools.GetToolStatus(_ssh);

        private StreamPlayerViewModel? _focusedPlayer;
        // When set, one camera fills the streaming area instead of the grid. Only
        // the focused player keeps a live connection while focused.
        public StreamPlayerViewModel? FocusedPlayer
        {
            get => _focusedPlayer;
            private set
            {
                if (SetProperty(ref _focusedPlayer, value))
                {
                    OnPropertyChanged(nameof(IsFocused));
                    OnPropertyChanged(nameof(IsGridMode));
                    OnPropertyChanged(nameof(DisplayedPlayers));
                    UpdateVisibility();
                }
            }
        }

        public bool IsFocused => FocusedPlayer != null;
        public bool IsGridMode => FocusedPlayer == null;

        // Raised by ToggleFullScreenCommand; the window handles the actual toggle.
        public event EventHandler? FullScreenToggleRequested;

        public bool IsWorkspaceEditorVisible => !ShowSettings && !IsStreaming && SelectedWorkspace != null;
        // The grid view stays visible in both layouts; focus is handled inside it
        // by swapping DisplayedPlayers, so a single set of players stays connected.
        public bool IsStreamGridVisible => IsStreaming && !ShowSettings;
        public bool IsSettingsVisible => ShowSettings;

        public RelayCommand AddWorkspaceCommand { get; }
        public RelayCommand DeleteWorkspaceCommand { get; }
        public RelayCommand ShowSettingsCommand { get; }
        public RelayCommand OpenClusterShellCommand { get; }
        public RelayCommand StartStreamingCommand { get; }
        public RelayCommand StopStreamingCommand { get; }
        public RelayCommand ClearCredentialsCommand { get; }
        public RelayCommand<StreamPlayerViewModel> FocusCameraCommand { get; }
        public RelayCommand ShowAllCamerasCommand { get; }
        public RelayCommand ToggleFullScreenCommand { get; }

        public MainViewModel()
        {
            _store = new WorkspaceStore();
            _ssh = new SshService();
            _streamer = new StreamController(_ssh);

            _streamer.PropertyChanged += (s, e) =>
            {
                OnPropertyChanged(e.PropertyName ?? string.Empty);

                if (e.PropertyName == nameof(StreamController.IsStreaming) || e.PropertyName == nameof(StreamController.Status))
                {
                    if (!_streamer.IsStreaming)
                        FocusedPlayer = null;

                    UpdateVisibility();
                    UpdateCommands();
                }
            };

            foreach (var w in _store.Workspaces)
            {
                var wv = new WorkspaceViewModel(w, CredentialStore.Instance);
                WireWorkspace(wv);
                Workspaces.Add(wv);
            }

            Workspaces.CollectionChanged += OnWorkspacesChanged;
            SelectedWorkspace = Workspaces.FirstOrDefault();

            AddWorkspaceCommand = new RelayCommand(AddWorkspace);
            DeleteWorkspaceCommand = new RelayCommand(DeleteWorkspace, () => SelectedWorkspace != null);
            ShowSettingsCommand = new RelayCommand(() => ShowSettings = true);
            OpenClusterShellCommand = new RelayCommand(OpenClusterShell, () => SelectedWorkspace != null);
            StartStreamingCommand = new RelayCommand(StartStreaming, () => SelectedWorkspace != null && !IsStreaming);
            StopStreamingCommand = new RelayCommand(StopStreaming, () => IsStreaming);
            ClearCredentialsCommand = new RelayCommand(ClearCredentials);
            FocusCameraCommand = new RelayCommand<StreamPlayerViewModel>(player => FocusedPlayer = player);
            ShowAllCamerasCommand = new RelayCommand(() => FocusedPlayer = null);
            ToggleFullScreenCommand = new RelayCommand(() => FullScreenToggleRequested?.Invoke(this, EventArgs.Empty));
        }

        private void UpdateVisibility()
        {
            OnPropertyChanged(nameof(IsWorkspaceEditorVisible));
            OnPropertyChanged(nameof(IsStreamGridVisible));
            OnPropertyChanged(nameof(IsSettingsVisible));
        }

        private void WireWorkspace(WorkspaceViewModel wv)
        {
            wv.PropertyChanged += (s, e) => SaveWorkspaces();

            wv.Cameras.CollectionChanged += (s, e) =>
            {
                if (e.NewItems != null)
                {
                    foreach (CameraViewModel cv in e.NewItems)
                        cv.PropertyChanged += (s2, e2) => SaveWorkspaces();
                }

                SaveWorkspaces();
            };

            foreach (var cv in wv.Cameras)
                cv.PropertyChanged += (s, e) => SaveWorkspaces();
        }

        private void OnWorkspacesChanged(object? sender, NotifyCollectionChangedEventArgs e)
        {
            if (e.NewItems != null)
            {
                foreach (WorkspaceViewModel wv in e.NewItems)
                    WireWorkspace(wv);
            }

            SaveWorkspaces();
        }

        private void SaveWorkspaces()
        {
            _store.Workspaces = Workspaces.Select(wv => wv.Model).ToList();
            _store.Save();
        }

        private void AddWorkspace()
        {
            var w = new CameraWorkspace { Name = "New workspace" };
            var wv = new WorkspaceViewModel(w, CredentialStore.Instance);
            Workspaces.Add(wv);
            SelectedWorkspace = wv;
        }

        private void DeleteWorkspace()
        {
            if (SelectedWorkspace == null)
                return;

            var result = MessageBox.Show($"Delete \"{SelectedWorkspace.Name}\"?",
                "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question);

            if (result != MessageBoxResult.Yes)
                return;

            Workspaces.Remove(SelectedWorkspace);
            SelectedWorkspace = Workspaces.FirstOrDefault();
        }

        private void OpenClusterShell()
        {
            var error = ClusterShellService.Open(SelectedWorkspace!.Model, _ssh);
            if (!string.IsNullOrEmpty(error))
                MessageBox.Show(error, "Cluster shell");
        }

        private void StartStreaming()
        {
            var ws = SelectedWorkspace!.Model;
            var missing = CredentialStore.Instance.MissingAccounts(ws);

            if (missing.Count > 0)
            {
                var dlg = new PasswordPromptWindow(ws.Name, !string.IsNullOrEmpty(ws.JumpHost), ws.JumpHost);
                if (dlg.ShowDialog() != true)
                    return;

                foreach (var cam in ws.Cameras)
                    CredentialStore.Instance.Passwords[cam.CredentialAccount] = dlg.CameraPassword;

                if (!string.IsNullOrEmpty(ws.JumpHost))
                    CredentialStore.Instance.Passwords[ws.JumpHost] = dlg.JumpPassword;
            }

            _streamer.Start(ws);
        }

        private void StopStreaming() => _streamer.Stop();

        private void ClearCredentials()
        {
            CredentialStore.Instance.Clear();
            OnPropertyChanged(nameof(BundledToolsStatus));
        }

        private static void UpdateCommands()
            => CommandManager.InvalidateRequerySuggested();

        public void Dispose() => _streamer.Dispose();
    }
}
