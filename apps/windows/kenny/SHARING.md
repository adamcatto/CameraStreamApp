# Sharing the Kenny Windows build

The `kenny-CameraStream-Windows.zip` produced by `package-kenny-windows.ps1` contains a fully self-contained Windows app plus the bundled Kenny workspace and credentials.

## How to share

1. Copy `dist/windows/kenny-CameraStream-Windows.zip` to the target PC.
2. Extract the zip.
3. Run `Install Kenny Camera Stream.bat` inside the extracted folder.
4. The batch file copies the app to `%LOCALAPPDATA%\CameraStream`, restricts `kenny-credentials.json` to the installing user, and launches the app.

## Important

- Do **not** redistribute the zip publicly. It contains lab-specific credentials.
- If the target PC does not have Windows Terminal (`wt.exe`) installed, the **Open cluster shell** button will fall back to opening each SSH session in a separate command window.
- The bundled credentials are loaded automatically on first launch and never written back to the app bundle.
