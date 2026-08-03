param([string]$prompt = "")

$path = $env:CAMERA_STREAM_CREDENTIALS_FILE
$fallback = $env:CAMERA_STREAM_KEYCHAIN_ACCOUNT

if (-not $path -or -not (Test-Path $path)) {
    exit 1
}

try {
    $json = Get-Content -Path $path -Raw | ConvertFrom-Json
} catch {
    exit 1
}

$account = $null
$match = [regex]::Match($prompt, '[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+')
if ($match.Success) {
    $account = $match.Value
}

if (-not $account) {
    $account = $fallback
}

function Get-PasswordForAccount($credentials, $target) {
    if (-not $target) {
        return $null
    }

    foreach ($property in $credentials.PSObject.Properties) {
        if ($property.Name -eq $target) {
            return $property.Value
        }
    }

    if ($target -match '@(.+)$') {
        $hostPart = $matches[1]
        foreach ($property in $credentials.PSObject.Properties) {
            if ($property.Name -like "*@$hostPart") {
                return $property.Value
            }
        }
    }

    return $null
}

$password = Get-PasswordForAccount $json $account
if (-not $password -and $fallback -and $fallback -ne $account) {
    $password = Get-PasswordForAccount $json $fallback
}

if (-not $password) {
    exit 1
}

[Console]::Out.Write($password)
[Console]::Out.Flush()
