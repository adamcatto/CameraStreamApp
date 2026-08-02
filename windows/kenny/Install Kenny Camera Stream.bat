@echo off
setlocal
set "SOURCE=%~dp0"
set "DEST=%LOCALAPPDATA%\CameraStream"

echo Installing Kenny Camera Stream from: %SOURCE%
echo Installing to: %DEST%
echo.

if not exist "%SOURCE%CameraStream.Windows.exe" (
    echo ERROR: CameraStream.Windows.exe was not found next to this installer.
    echo Extract the full zip first. This folder should contain the .exe, .dll files,
    echo kenny-workspaces.json, kenny-credentials.json, and this .bat file.
    echo.
    dir "%SOURCE%"
    pause
    exit /b 1
)

if not exist "%SOURCE%kenny-workspaces.json" (
    echo ERROR: kenny-workspaces.json is missing from the install folder.
    pause
    exit /b 1
)

if not exist "%SOURCE%kenny-credentials.json" (
    echo ERROR: kenny-credentials.json is missing from the install folder.
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
    echo Check Windows Security protection history, then try running the .exe directly
    echo from the extracted zip folder.
    dir "%DEST%"
    pause
    exit /b 1
)

echo Restricting bundled credentials to your user account ...
if exist "%DEST%\kenny-credentials.json" (
    icacls "%DEST%\kenny-credentials.json" /inheritance:r >nul
    icacls "%DEST%\kenny-credentials.json" /grant:r "%USERNAME%:(R)" >nul
)

echo Done. Starting Camera Stream...
start "" "%DEST%\CameraStream.Windows.exe"
