@echo off
setlocal
set "APP=%~dp0CameraStream\CameraStream.Windows.exe"

if not exist "%APP%" (
    echo Camera Stream was not found at:
    echo   %APP%
    echo.
    echo Extract the full zip first. You should see a CameraStream folder next to this file.
    pause
    exit /b 1
)

start "" "%APP%"
