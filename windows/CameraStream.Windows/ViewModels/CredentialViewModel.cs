using System.ComponentModel;
using System.Runtime.CompilerServices;
using CameraStream.Windows.Services;

namespace CameraStream.Windows.ViewModels
{
    public class CredentialViewModel : INotifyPropertyChanged
    {
        private readonly CredentialStore _store;
        private string _password;

        public string Account { get; }
        public string Label { get; }

        public string Password
        {
            get => _password;
            set
            {
                if (_password == value)
                    return;

                _password = value;
                _store.SetPassword(Account, value);
                OnPropertyChanged();
            }
        }

        public CredentialViewModel(CredentialStore store, string account, string label, string password)
        {
            _store = store;
            Account = account;
            Label = label;
            _password = password;
        }

        public void RefreshFromStore()
        {
            _store.Passwords.TryGetValue(Account, out var pw);
            SetValue(pw ?? "");
        }

        public void ClearPassword()
        {
            SetValue("");
        }

        private void SetValue(string value)
        {
            if (_password == value)
                return;

            _password = value;
            OnPropertyChanged();
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        private void OnPropertyChanged([CallerMemberName] string propertyName = "")
            => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
