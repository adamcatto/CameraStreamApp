#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $root
$project = Join-Path $root "CameraStream.Windows\CameraStream.Windows.csproj"
$publishDir = Join-Path $root "publish"
$distDir = Join-Path $repoRoot "dist\windows"
$appDir = Join-Path $distDir "CameraStream"
$zip = Join-Path $distDir "CameraStream-Windows.zip"

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
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        -o $publishDir

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed"
    }
}

function Package() {
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    Copy-Item (Join-Path $root "Install Camera Stream.bat") $publishDir
    Copy-Item "$publishDir\*" $appDir -Recurse -Force
    Compress-Archive -Path "$appDir\*" -DestinationPath $zip -Force
    Write-Host "Created $zip"
}

$smokeTest = Join-Path $root "scripts\smoke-test-windows.ps1"

Clean
Build
& $smokeTest
Package
