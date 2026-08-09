using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using CameraStream.Windows.Models;
using CameraStream.Windows.ViewModels;

namespace CameraStream.Windows.Services
{
    public class CredentialStore
    {
        private static readonly Lazy<CredentialStore> _instance = new(() => new CredentialStore());
        public static CredentialStore Instance => _instance.Value;

        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            AllowTrailingCommas = true
        };

        public Dictionary<string, string> Passwords { get; } = new();
        public ObservableCollection<CredentialViewModel> Items { get; } = new();

        private CredentialStore()
        {
            var path = BundledTools.GetBundledPath("profiles-credentials.json");
            if (path == null || !File.Exists(path))
                return;

            try
            {
                var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path), JsonOptions);
                if (dict != null)
                {
                    foreach (var kv in dict)
                        Passwords[kv.Key] = kv.Value;
                }
            }
            catch
            {
            }
        }

        public List<string> MissingAccounts(CameraWorkspace workspace)
        {
            var accounts = workspace.Cameras.Select(c => c.CredentialAccount).ToList();
            if (!string.IsNullOrEmpty(workspace.JumpHost))
                accounts.Add(workspace.JumpHost);

            return accounts
                .Where(a => !Passwords.ContainsKey(a) || string.IsNullOrEmpty(Passwords[a]))
                .ToList();
        }

        public void Clear()
        {
            Passwords.Clear();
            foreach (var item in Items)
                item.ClearPassword();
        }

        public void RefreshItems(List<WorkspaceViewModel> workspaces)
        {
            Items.Clear();

            foreach (var w in workspaces)
            {
                foreach (var c in w.Cameras)
                {
                    var account = c.CredentialAccount;
                    Passwords.TryGetValue(account, out var pw);
                    Items.Add(new CredentialViewModel(this, account, $"{c.Name} · {account}", pw ?? ""));
                }

                if (!string.IsNullOrEmpty(w.JumpHost))
                {
                    Passwords.TryGetValue(w.JumpHost, out var pw);
                    Items.Add(new CredentialViewModel(this, w.JumpHost, $"Jump host · {w.JumpHost}", pw ?? ""));
                }
            }
        }

        internal void SetPassword(string account, string password)
        {
            Passwords[account] = password;
        }
    }
}
