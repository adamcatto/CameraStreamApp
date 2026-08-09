using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using CameraStream.Windows.Models;

namespace CameraStream.Windows.Services
{
    public class WorkspaceStore
    {
        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = true,
            AllowTrailingCommas = true
        };

        private readonly string _filePath;

        public List<CameraWorkspace> Workspaces { get; set; }

        public WorkspaceStore()
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CameraStream");
            Directory.CreateDirectory(dir);

            _filePath = Path.Combine(dir, "workspaces.json");
            Workspaces = Load();
        }

        private List<CameraWorkspace> Load()
        {
            if (File.Exists(_filePath))
            {
                try
                {
                    var json = File.ReadAllText(_filePath);
                    var list = JsonSerializer.Deserialize<List<CameraWorkspace>>(json, JsonOptions);
                    if (list != null && list.Count > 0)
                        return list;
                }
                catch
                {
                    // Fall through to bundled or default.
                }
            }

            var bundled = LoadBundled();
            if (bundled != null)
            {
                Workspaces = bundled;
                Save();
                return bundled;
            }

            return new List<CameraWorkspace>
            {
                new()
                {
                    Name = "Example workspace",
                    Cameras = new List<CameraEndpoint>
                    {
                        new() { Name = "Camera 1", Host = "192.0.2.10" }
                    }
                }
            };
        }

        private List<CameraWorkspace>? LoadBundled()
        {
            var path = BundledTools.GetBundledPath("profiles-workspaces.json");
            if (path == null || !File.Exists(path))
                return null;

            try
            {
                var json = File.ReadAllText(path);
                var list = JsonSerializer.Deserialize<List<CameraWorkspace>>(json, JsonOptions);
                if (list != null && list.Count > 0)
                    return list;
            }
            catch
            {
            }

            return null;
        }

        public void Save()
        {
            try
            {
                File.WriteAllText(_filePath, JsonSerializer.Serialize(Workspaces, JsonOptions));
            }
            catch
            {
            }
        }
    }
}
