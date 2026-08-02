using System.Windows;
using System.Windows.Controls;

namespace CameraStream.Windows.Views
{
    public partial class SecureTextBox : UserControl
    {
        private bool _updating;

        public SecureTextBox()
        {
            InitializeComponent();
        }

        public static readonly DependencyProperty PasswordProperty =
            DependencyProperty.Register(nameof(Password), typeof(string), typeof(SecureTextBox),
                new FrameworkPropertyMetadata(string.Empty, FrameworkPropertyMetadataOptions.BindsTwoWayByDefault, OnPasswordChanged));

        public string Password
        {
            get => (string)GetValue(PasswordProperty);
            set => SetValue(PasswordProperty, value);
        }

        public static readonly DependencyProperty IsRevealedProperty =
            DependencyProperty.Register(nameof(IsRevealed), typeof(bool), typeof(SecureTextBox),
                new PropertyMetadata(false, OnIsRevealedChanged));

        public bool IsRevealed
        {
            get => (bool)GetValue(IsRevealedProperty);
            set => SetValue(IsRevealedProperty, value);
        }

        private void Root_Loaded(object sender, RoutedEventArgs e) => UpdateVisibility();

        private static void OnPasswordChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is SecureTextBox s)
                s.Sync((string)e.NewValue);
        }

        private static void OnIsRevealedChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is SecureTextBox s)
                s.UpdateVisibility();
        }

        private void Sync(string password)
        {
            if (_updating)
                return;

            _updating = true;

            var p = password ?? string.Empty;
            if (PasswordBox.Password != p)
                PasswordBox.Password = p;
            if (TextBox.Text != p)
                TextBox.Text = p;

            _updating = false;
        }

        private void PasswordBox_PasswordChanged(object sender, RoutedEventArgs e)
        {
            if (_updating)
                return;

            _updating = true;

            var p = PasswordBox.Password;
            TextBox.Text = p;
            SetValue(PasswordProperty, p);

            _updating = false;
        }

        private void TextBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (_updating)
                return;

            _updating = true;

            var p = TextBox.Text;
            PasswordBox.Password = p;
            SetValue(PasswordProperty, p);

            _updating = false;
        }

        private void UpdateVisibility()
        {
            if (IsRevealed)
            {
                PasswordBox.Visibility = Visibility.Collapsed;
                TextBox.Visibility = Visibility.Visible;
            }
            else
            {
                PasswordBox.Visibility = Visibility.Visible;
                TextBox.Visibility = Visibility.Collapsed;
            }
        }
    }
}
