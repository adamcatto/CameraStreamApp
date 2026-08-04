using System;
using System.Collections.Generic;

namespace CameraStream.Windows.Models
{
    public class CameraWorkspace
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Name { get; set; } = "";
        public List<CameraEndpoint> Cameras { get; set; } = new();
        public string? JumpHost { get; set; }
    }
}
