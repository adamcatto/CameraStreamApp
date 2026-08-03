@echo off
setlocal
set "SOURCE=%~dp0CameraStream"
set "DEST=%LOCALAPPDATA%\CameraStream"

echo Installing Kenny Camera Stream from: %SOURCE%
echo Installing to: %DEST%
echo.

if not exist "%SOURCE%\CameraStream.Windows.exe" (
    echo ERROR: CameraStream.Windows.exe was not found in the CameraStream folder.
    echo Extract the full zip first. You should see:
    echo   Install Kenny Camera Stream.bat
    echo   Run Camera Stream.bat
    echo   CameraStream\CameraStream.Windows.exe
    echo.
    dir "%~dp0"
    pause
    exit /b 1
)

if not exist "%SOURCE%\kenny-workspaces.json" (
    echo ERROR: kenny-workspaces.json is missing from the CameraStream folder.
    pause
    exit /b 1
)

if not exist "%SOURCE%\kenny-credentials.json" (
    echo ERROR: kenny-credentials.json is missing from the CameraStream folder.
    pause
    exit /b 1
)

taskkill /IM CameraStream.Windows.exe /F >nul 2>&1

if not exist "%DEST%" mkdir "%DEST%"

if exist "%DEST%\kenny-credentials.json" (
    echo Updating existing install ...
    attrib -R "%DEST%\kenny-credentials.json" >nul 2>&1
    icacls "%DEST%\kenny-credentials.json" /inheritance:e >nul 2>&1
    icacls "%DEST%\kenny-credentials.json" /grant "%USERNAME%:F" >nul 2>&1
    del /f /q "%DEST%\kenny-credentials.json" >nul 2>&1
)

robocopy "%SOURCE%" "%DEST%" /E /NFL /NDL /NJH /NJS /NC /NS /NP
set "ROBOCOPY_EXIT=%ERRORLEVEL%"
if %ROBOCOPY_EXIT% GEQ 8 (
    echo ERROR: robocopy failed with exit code %ROBOCOPY_EXIT%.
    if exist "%DEST%\kenny-credentials.json" (
        echo Could not update kenny-credentials.json. Close Camera Stream and try again.
    )
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

echo Restricting bundled credentials to your user account ...
if exist "%DEST%\kenny-credentials.json" (
    icacls "%DEST%\kenny-credentials.json" /inheritance:r >nul 2>&1
    icacls "%DEST%\kenny-credentials.json" /grant:r "%USERNAME%:(R)" >nul 2>&1
)

echo Done. Starting Camera Stream...
start "" "%DEST%\CameraStream.Windows.exe"
