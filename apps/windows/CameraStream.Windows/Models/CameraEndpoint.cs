using System;

namespace CameraStream.Windows.Models
{
    public class CameraEndpoint
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Name { get; set; } = "";
        public string Host { get; set; } = "";
        public string Username { get; set; } = "pi";
        public int Port { get; set; } = 8888;
        public CameraSettings? Settings { get; set; }

        public string Address => $"{Username}@{Host}";
        public string CredentialAccount => $"{Username}@{Host}";
    }
}
