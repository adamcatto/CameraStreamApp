#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$publishDir = Join-Path $root "publish"

$required = @(
    "CameraStream.Windows.exe",
    "CameraSSHAskpass.cmd",
    "CameraSSHAskpass.ps1",
    "LibVLCSharp.dll",
    "libvlc\win-x64\libvlc.dll"
)

$missing = @()
foreach ($item in $required) {
    $path = Join-Path $publishDir $item
    if (-not (Test-Path $path)) {
        $missing += $item
    }
}

if ($missing) {
    Write-Error "Missing files in ${publishDir}:`n$($missing -join "`n")"
    exit 1
}

Write-Host "Smoke test passed: $publishDir contains required files."
