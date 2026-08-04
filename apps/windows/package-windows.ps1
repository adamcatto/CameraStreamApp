#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $root "..\..")
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
        -p:PublishSingleFile=false `
        -o $publishDir

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed"
    }

    $askpassProject = Join-Path $root "CameraSSHAskpass\CameraSSHAskpass.csproj"
    dotnet publish $askpassProject -c Release -r win-x64 --self-contained true `
        -p:PublishSingleFile=true `
        -o $publishDir

    if ($LASTEXITCODE -ne 0) {
        throw "CameraSSHAskpass publish failed"
    }
}

function Package() {
    $bundleRoot = Join-Path $distDir "CameraStream-Windows-bundle"
    $appSub = Join-Path $bundleRoot "CameraStream"
    New-Item -ItemType Directory -Path $appSub -Force | Out-Null
    Copy-Item "$publishDir\*" $appSub -Recurse -Force
    Copy-Item (Join-Path $root "Install Camera Stream.bat") $bundleRoot
    Copy-Item (Join-Path $root "Run Camera Stream.bat") $bundleRoot
    Compress-Archive -Path "$bundleRoot\*" -DestinationPath $zip -Force
    Remove-Item $bundleRoot -Recurse -Force
    Write-Host "Created $zip"
}

$smokeTest = Join-Path $root "scripts\smoke-test-windows.ps1"

Clean
Build
& $smokeTest
Package
