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

$account = $fallback
$match = [regex]::Match($prompt, '[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+')
if ($match.Success) {
    $account = $match.Value
}

if (-not $account) {
    exit 1
}

$password = $null
foreach ($property in $json.PSObject.Properties) {
    if ($property.Name -eq $account) {
        $password = $property.Value
        break
    }
}

if (-not $password -and $fallback) {
    foreach ($property in $json.PSObject.Properties) {
        if ($property.Name -eq $fallback) {
            $password = $property.Value
            break
        }
    }
}

if (-not $password) {
    exit 1
}

[Console]::Out.Write($password)
[Console]::Out.Flush()
