#Requires -Version 7.0
$ErrorActionPreference = "Stop"

param(
    [Parameter(Mandatory)] [string]$WorkspacesPath,
    [Parameter(Mandatory)] [string]$CredentialsPath,
    [Parameter(Mandatory)] [string]$OutputPath
)

$workspaces = Get-Content $WorkspacesPath -Raw | ConvertFrom-Json -AsHashtable
$raw = Get-Content $CredentialsPath -Raw | ConvertFrom-Json -AsHashtable

$byName = @{}

if ($raw -is [array]) {
    foreach ($entry in $raw) {
        $byName[$entry["workspaceName"]] = $entry
    }
} elseif ($raw -is [hashtable]) {
    if ($raw.ContainsKey("workspaces")) {
        foreach ($name in $raw["workspaces"].Keys) {
            $entry = $raw["workspaces"][$name].Clone()
            $entry["workspaceName"] = $name
            $byName[$name] = $entry
        }
    } else {
        $byName["__accounts__"] = $raw
    }
} else {
    throw "Credentials file must be a JSON array or object."
}

if ($byName.ContainsKey("__accounts__")) {
    $accountCredentials = $byName["__accounts__"]
    if (-not $accountCredentials -or $accountCredentials.Values.Where({ -not ($_ -is [string] -and $_.Trim()) }, 'First').Count -gt 0) {
        throw "Account credentials file has missing passwords."
    }
    $accountCredentials | ConvertTo-Json -Depth 10 | Set-Content $OutputPath
    exit 0
}

$accountCredentials = @{}
foreach ($workspace in $workspaces) {
    $name = $workspace["name"]
    $entry = $byName[$name]
    if (-not $entry) {
        throw "Missing credentials entry for workspace: $name"
    }

    $cameraPassword = $entry["cameraPassword"]
    if (-not ($cameraPassword -is [string] -and $cameraPassword.Trim())) {
        throw "Missing cameraPassword for workspace: $name"
    }

    foreach ($camera in $workspace["cameras"]) {
        $username = if ($camera.ContainsKey("username")) { $camera["username"] } else { "pi" }
        $host = $camera["host"]
        if ($host) {
            $accountCredentials["$username@$host"] = $cameraPassword
        }
    }

    $jumpHost = $workspace["jumpHost"]
    if ($jumpHost) {
        $jumpPassword = $entry["jumpPassword"]
        if (-not ($jumpPassword -is [string] -and $jumpPassword.Trim())) {
            throw "Missing jumpPassword for workspace: $name"
        }
        $accountCredentials[$jumpHost] = $jumpPassword
    }
}

if ($accountCredentials.Count -eq 0) {
    throw "No account credentials were generated."
}

$accountCredentials | ConvertTo-Json -Depth 10 | Set-Content $OutputPath
