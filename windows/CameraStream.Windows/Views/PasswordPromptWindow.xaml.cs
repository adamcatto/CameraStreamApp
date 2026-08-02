using System.Windows;

namespace CameraStream.Windows.Views
{
    public partial class PasswordPromptWindow : Window
    {
        public string CameraPassword { get; private set; } = "";
        public string JumpPassword { get; private set; } = "";

        public PasswordPromptWindow(string workspaceName, bool hasJumpHost, string? jumpHost = null)
        {
            InitializeComponent();

            MessageText.Text = $"Credentials needed for {workspaceName}. Passwords are used only for this app session and are discarded when you quit.";

            if (hasJumpHost)
            {
                JumpHostPanel.Visibility = Visibility.Visible;
                JumpHostLabel.Text = $"Password for jump host {jumpHost ?? ""}";
            }
        }

        private void Start_Click(object sender, RoutedEventArgs e)
        {
            CameraPassword = CameraPasswordBox.Password;
            JumpPassword = JumpPasswordBox.Password;
            DialogResult = true;
        }

        private void Cancel_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
        }
    }
}
