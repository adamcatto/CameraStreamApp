using System;

namespace CameraStream.Windows.ViewModels
{
    public class StreamPlayerViewModel : ObservableObject
    {
        private string _name;

        public Guid Id { get; }

        public string Name
        {
            get => _name;
            set => SetProperty(ref _name, value);
        }

        public string Host { get; }
        public int Port { get; }

        public StreamPlayerViewModel(Guid id, string name, string host, int port)
        {
            Id = id;
            _name = name;
            Host = host;
            Port = port;
        }
    }
}
