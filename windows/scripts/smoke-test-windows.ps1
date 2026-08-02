#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$publishDir = Join-Path $root "publish"

$required = @(
    "CameraStream.Windows.exe",
    "CameraSSHAskpass.cmd",
    "CameraSSHAskpass.ps1",
    "libvlc.dll",
    "LibVLCSharp.dll"
)

$missing = $required | Where-Object { -not (Test-Path (Join-Path $publishDir $_)) }

if ($missing) {
    Write-Error "Missing files in ${publishDir}:`n$($missing -join "`n")"
    exit 1
}

Write-Host "Smoke test passed: $publishDir contains required files."
