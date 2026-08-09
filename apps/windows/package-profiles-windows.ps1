#Requires -Version 7.0
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $root "..\..")
$project = Join-Path $root "CameraStream.Windows\CameraStream.Windows.csproj"
$bundler = Join-Path $root "scripts\bundle-profiles-credentials.ps1"
$publishDir = Join-Path $root "publish"
$distDir = Join-Path $repoRoot "dist\windows"
$appDir = Join-Path $distDir "ProfilesCameraStream"
$zip = Join-Path $distDir "profiles-CameraStream-Windows.zip"

$workspacesSource = $args[0]
if (-not $workspacesSource) {
    $candidates = @(
        "$env:LOCALAPPDATA\CameraStream\workspaces.json",
        (Join-Path $repoRoot "config\sandbox\workspaces.local.json")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $workspacesSource = $c
            break
        }
    }
}

$credentialsSource = $args[1]
if (-not $credentialsSource) {
    $candidates = @(
        (Join-Path $repoRoot "config\profiles\credentials.local.json"),
        (Join-Path $repoRoot "config\sandbox\credentials.local.json")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $credentialsSource = $c
            break
        }
    }
}

if (-not $workspacesSource -or -not (Test-Path $workspacesSource)) {
    throw @"
No workspace file found to bundle.

Provide paths:
  .\package-profiles-windows.ps1 [workspaces.json] [credentials.json]

Or ensure one of these exists:
  %APPDATA%\CameraStream\workspaces.json
  config\sandbox\workspaces.local.json
"@
}

if (-not $credentialsSource -or -not (Test-Path $credentialsSource)) {
    $template = Join-Path $repoRoot "config\profiles\credentials.local.json"
    $generateScript = Join-Path $repoRoot "config\profiles\generate-credentials-template.sh"
    if (Test-Path $generateScript) {
        & bash $generateScript $workspacesSource $template
    }
    throw @"
No credentials file found. Generated template at $template.
Add passwords, then run .\package-profiles-windows.ps1 again.
"@
}

$null = Get-Content $workspacesSource -Raw | ConvertFrom-Json -AsHashtable
$null = Get-Content $credentialsSource -Raw | ConvertFrom-Json -AsHashtable

function Clean() {
    if (Test-Path $publishDir) {
        Remove-Item $publishDir -Recurse -Force
    }
    if (Test-Path $distDir) {
        Remove-Item $distDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

function Build() {
    $bundleFile = Join-Path $env:TEMP "profiles-credentials.bundle.json"
    pwsh -NoProfile -File $bundler -WorkspacesPath $workspacesSource -CredentialsPath $credentialsSource -OutputPath $bundleFile

    if ($LASTEXITCODE -ne 0) {
        throw "Credential bundling failed"
    }

    dotnet publish $project -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=false `
        -o $publishDir

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed"
    }

    Copy-Item $workspacesSource (Join-Path $publishDir "profiles-workspaces.json")
    Copy-Item $bundleFile (Join-Path $publishDir "profiles-credentials.json")
    Copy-Item (Join-Path $root "profiles\Install Profiles Camera Stream.bat") $publishDir
    Remove-Item $bundleFile -Force
}

function Package() {
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    Copy-Item "$publishDir\*" $appDir -Recurse -Force
    Compress-Archive -Path "$appDir\*" -DestinationPath $zip -Force
    Write-Host "Created $zip"
}

Clean
Build
Package

Write-Host "Bundled workspaces from: $workspacesSource"
Write-Host "Bundled credentials from: $credentialsSource"
Write-Host "Share this zip privately - it contains workspace hosts and passwords."
