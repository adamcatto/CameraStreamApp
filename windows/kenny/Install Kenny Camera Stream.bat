@echo off
setlocal
set "SOURCE=%~dp0"
set "DEST=%LOCALAPPDATA%\CameraStream"

if not exist "%SOURCE%CameraStream.Windows.exe" (
    echo CameraStream.Windows.exe not found next to this installer.
    pause
    exit /b 1
)

echo Installing Kenny Camera Stream to %DEST% ...
if not exist "%DEST%" mkdir "%DEST%"
robocopy "%SOURCE%" "%DEST%" /E /NFL /NDL

echo Restricting bundled credentials to your user account ...
if exist "%DEST%\kenny-credentials.json" (
    icacls "%DEST%\kenny-credentials.json" /inheritance:r >nul
    icacls "%DEST%\kenny-credentials.json" /grant:r "%USERNAME%:(R)" >nul
)

echo Done. Starting Camera Stream...
start "" "%DEST%\CameraStream.Windows.exe"
