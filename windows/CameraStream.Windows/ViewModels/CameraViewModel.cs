using CameraStream.Windows.Models;
using CameraStream.Windows.Services;

namespace CameraStream.Windows.ViewModels
{
    public class CameraViewModel : ObservableObject
    {
        public CameraEndpoint Model { get; }
        private readonly CredentialStore _credentials;

        public string Name
        {
            get => Model.Name;
            set { Model.Name = value; OnPropertyChanged(); }
        }

        public string Host
        {
            get => Model.Host;
            set { Model.Host = value; OnPropertyChanged(); }
        }

        public string Username
        {
            get => Model.Username;
            set { Model.Username = value; OnPropertyChanged(); }
        }

        public int Port
        {
            get => Model.Port;
            set { Model.Port = value; OnPropertyChanged(); }
        }

        public string CredentialAccount => Model.CredentialAccount;

        public CameraViewModel(CameraEndpoint model, CredentialStore credentials)
        {
            Model = model;
            _credentials = credentials;
        }
    }
}
