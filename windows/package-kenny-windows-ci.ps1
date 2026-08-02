#Requires -Version 5.1
param(
    [Parameter(Mandatory)] [string]$WorkspacesPath,
    [Parameter(Mandatory)] [string]$CredentialsPath
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $root
$project = Join-Path $root "CameraStream.Windows\CameraStream.Windows.csproj"
$publishDir = Join-Path $root "publish"
$distDir = Join-Path $repoRoot "dist\windows"
$appDir = Join-Path $distDir "KennyCameraStream"
$zip = Join-Path $distDir "kenny-CameraStream-Windows.zip"

if (-not (Test-Path $WorkspacesPath)) {
    throw "Workspaces file not found: $WorkspacesPath"
}
if (-not (Test-Path $CredentialsPath)) {
    throw "Credentials file not found: $CredentialsPath"
}

$null = Get-Content $WorkspacesPath -Raw | ConvertFrom-Json
$null = Get-Content $CredentialsPath -Raw | ConvertFrom-Json

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
    dotnet publish $project -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=false `
        -o $publishDir

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed"
    }

    Copy-Item $WorkspacesPath (Join-Path $publishDir "kenny-workspaces.json")
    Copy-Item $CredentialsPath (Join-Path $publishDir "kenny-credentials.json")
    Copy-Item (Join-Path $root "kenny\Install Kenny Camera Stream.bat") $publishDir
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
