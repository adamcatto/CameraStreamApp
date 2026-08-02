@echo off
setlocal
set "SOURCE=%~dp0"
set "DEST=%LOCALAPPDATA%\CameraStream"

echo Installing from: %SOURCE%
echo Installing to:   %DEST%
echo.

if not exist "%SOURCE%CameraStream.Windows.exe" (
    echo ERROR: CameraStream.Windows.exe was not found next to this installer.
    echo.
    echo Make sure you extracted the full zip first. This folder should contain
    echo CameraStream.Windows.exe, several .dll files, and this .bat file.
    echo.
    dir "%SOURCE%"
    pause
    exit /b 1
)

echo Files in the install folder:
dir /b "%SOURCE%"
echo.

if not exist "%DEST%" mkdir "%DEST%"
robocopy "%SOURCE%" "%DEST%" /E /NFL /NDL /NJH /NJS /NC /NS /NP
set "ROBOCOPY_EXIT=%ERRORLEVEL%"
if %ROBOCOPY_EXIT% GEQ 8 (
    echo ERROR: robocopy failed with exit code %ROBOCOPY_EXIT%.
    pause
    exit /b 1
)

if not exist "%DEST%\CameraStream.Windows.exe" (
    echo ERROR: Install finished but CameraStream.Windows.exe is missing in:
    echo   %DEST%
    echo.
    echo Windows Security may have removed it. Check Protection history, then try
    echo running CameraStream.Windows.exe directly from the extracted zip folder.
    echo.
    dir "%DEST%"
    pause
    exit /b 1
)

echo Done. Starting Camera Stream...
start "" "%DEST%\CameraStream.Windows.exe"
