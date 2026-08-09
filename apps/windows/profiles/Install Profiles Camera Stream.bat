@echo off
setlocal
set "SOURCE=%~dp0CameraStream"
set "DEST=%LOCALAPPDATA%\CameraStream"

echo Installing Profiles Camera Stream from: %SOURCE%
echo Installing to: %DEST%
echo.

if not exist "%SOURCE%\CameraStream.Windows.exe" (
    echo ERROR: CameraStream.Windows.exe was not found in the CameraStream folder.
    echo Extract the full zip first. You should see:
    echo   Install Profiles Camera Stream.bat
    echo   Run Camera Stream.bat
    echo   CameraStream\CameraStream.Windows.exe
    echo.
    dir "%~dp0"
    pause
    exit /b 1
)

if not exist "%SOURCE%\profiles-workspaces.json" (
    echo ERROR: profiles-workspaces.json is missing from the CameraStream folder.
    pause
    exit /b 1
)

if not exist "%SOURCE%\profiles-credentials.json" (
    echo ERROR: profiles-credentials.json is missing from the CameraStream folder.
    pause
    exit /b 1
)

taskkill /IM CameraStream.Windows.exe /F >nul 2>&1

if not exist "%DEST%" mkdir "%DEST%"

if exist "%DEST%\profiles-credentials.json" (
    echo Updating existing install ...
    attrib -R "%DEST%\profiles-credentials.json" >nul 2>&1
    icacls "%DEST%\profiles-credentials.json" /inheritance:e >nul 2>&1
    icacls "%DEST%\profiles-credentials.json" /grant "%USERNAME%:F" >nul 2>&1
    del /f /q "%DEST%\profiles-credentials.json" >nul 2>&1
)

robocopy "%SOURCE%" "%DEST%" /E /NFL /NDL /NJH /NJS /NC /NS /NP
set "ROBOCOPY_EXIT=%ERRORLEVEL%"
if %ROBOCOPY_EXIT% GEQ 8 (
    echo ERROR: robocopy failed with exit code %ROBOCOPY_EXIT%.
    if exist "%DEST%\profiles-credentials.json" (
        echo Could not update profiles-credentials.json. Close Camera Stream and try again.
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
if exist "%DEST%\profiles-credentials.json" (
    icacls "%DEST%\profiles-credentials.json" /inheritance:r >nul 2>&1
    icacls "%DEST%\profiles-credentials.json" /grant:r "%USERNAME%:(R)" >nul 2>&1
)

echo Done. Starting Camera Stream...
start "" "%DEST%\CameraStream.Windows.exe"
