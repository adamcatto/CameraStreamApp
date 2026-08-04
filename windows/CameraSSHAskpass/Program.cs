using System.Text.Json;
using System.Text.RegularExpressions;

var prompt = string.Join(' ', args);
var promptMatch = Regex.Match(prompt, @"[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+");

var credentialPath = Environment.GetEnvironmentVariable("CAMERA_STREAM_CREDENTIALS_FILE");
var fallback = Environment.GetEnvironmentVariable("CAMERA_STREAM_KEYCHAIN_ACCOUNT");

if (string.IsNullOrEmpty(credentialPath) || !File.Exists(credentialPath))
    return 1;

Dictionary<string, string>? credentials;
try
{
    credentials = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(credentialPath));
}
catch
{
    return 1;
}

if (credentials == null || credentials.Count == 0)
    return 1;

var account = promptMatch.Success ? promptMatch.Value : fallback;
if (string.IsNullOrEmpty(account))
    return 1;

if (!TryGetPassword(credentials, account, out var password)
    && (string.IsNullOrEmpty(fallback)
        || string.Equals(account, fallback, StringComparison.Ordinal)
        || !TryGetPassword(credentials, fallback, out password)))
    return 1;

Console.Out.WriteLine(password);
return 0;

static bool TryGetPassword(Dictionary<string, string> credentials, string account, out string password)
{
    if (credentials.TryGetValue(account, out password!) && !string.IsNullOrEmpty(password))
        return true;

    var at = account.IndexOf('@');
    if (at < 0)
    {
        password = "";
        return false;
    }

    var hostPart = account[(at + 1)..];
    foreach (var entry in credentials)
    {
        if (entry.Key.EndsWith("@" + hostPart, StringComparison.Ordinal) && !string.IsNullOrEmpty(entry.Value))
        {
            password = entry.Value;
            return true;
        }
    }

    password = "";
    return false;
}
