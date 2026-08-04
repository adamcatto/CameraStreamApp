using System.Collections.ObjectModel;
using CameraStream.Windows.Models;
using CameraStream.Windows.Services;

namespace CameraStream.Windows.ViewModels
{
    public class WorkspaceViewModel : ObservableObject
    {
        private readonly CredentialStore _credentials;

        public CameraWorkspace Model { get; }

        public string Name
        {
            get => Model.Name;
            set { Model.Name = value; OnPropertyChanged(); }
        }

        public string JumpHost
        {
            get => Model.JumpHost ?? "";
            set
            {
                Model.JumpHost = string.IsNullOrWhiteSpace(value) ? null : value;
                OnPropertyChanged();
            }
        }

        public ObservableCollection<CameraViewModel> Cameras { get; } = new();

        public RelayCommand AddCameraCommand { get; }
        public RelayCommand<CameraViewModel?> RemoveCameraCommand { get; }

        public WorkspaceViewModel(CameraWorkspace model, CredentialStore credentials)
        {
            Model = model;
            _credentials = credentials;

            foreach (var camera in model.Cameras)
                Cameras.Add(new CameraViewModel(camera, _credentials));

            AddCameraCommand = new RelayCommand(AddCamera);
            RemoveCameraCommand = new RelayCommand<CameraViewModel?>(RemoveCamera);
        }

        private void AddCamera()
        {
            var camera = new CameraEndpoint { Name = $"Camera {Cameras.Count + 1}" };
            Model.Cameras.Add(camera);
            Cameras.Add(new CameraViewModel(camera, _credentials));
        }

        private void RemoveCamera(CameraViewModel? vm)
        {
            if (vm == null)
                return;

            Model.Cameras.Remove(vm.Model);
            Cameras.Remove(vm);
        }
    }
}
