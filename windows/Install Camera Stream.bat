@echo off
setlocal
set "SOURCE=%~dp0CameraStream"
set "DEST=%LOCALAPPDATA%\CameraStream"

echo Installing from: %SOURCE%
echo Installing to:   %DEST%
echo.

if not exist "%SOURCE%\CameraStream.Windows.exe" (
    echo ERROR: CameraStream.Windows.exe was not found in the CameraStream folder.
    echo.
    echo Extract the full zip first. The folder next to this installer should contain:
    echo   CameraStream\CameraStream.Windows.exe
    echo.
    dir "%~dp0"
    pause
    exit /b 1
)

if not exist "%DEST%" mkdir "%DEST%"
robocopy "%SOURCE%" "%DEST%" /E /NFL /NDL /NJH /NJS /NC /NS /NP
set "ROBOCOPY_EXIT=%ERRORLEVEL%"
if %ROBOCOPY_EXIT% GEQ 8 (
    echo ERROR: robocopy failed with exit code %ROBOCOPY_EXIT%.
    pause
    exit /b 1
)

if not exist "%DEST%\CameraStream.Windows.exe" (
    echo ERROR: Install finished but CameraStream.Windows.exe is missing in %DEST%.
    echo Check Windows Security protection history, then try Run Camera Stream.bat instead.
    dir "%DEST%"
    pause
    exit /b 1
)

echo Done. Starting Camera Stream...
start "" "%DEST%\CameraStream.Windows.exe"
