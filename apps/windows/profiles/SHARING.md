# Sharing the Profiles Windows build

The `profiles-CameraStream-Windows.zip` produced by `package-profiles-windows.ps1` contains a fully self-contained Windows app plus bundled profile workspaces and credentials.

## How to share

1. Copy `dist/windows/profiles-CameraStream-Windows.zip` to the target PC.
2. Extract the zip.
3. Run `Install Profiles Camera Stream.bat` inside the extracted folder.
4. The batch file copies the app to `%LOCALAPPDATA%\CameraStream`, restricts `profiles-credentials.json` to the installing user, and launches the app.

## Important

- Do **not** redistribute the zip publicly. It contains private credentials.
- If the target PC does not have Windows Terminal (`wt.exe`) installed, the **Open cluster shell** button will fall back to opening each SSH session in a separate command window.
- The bundled credentials are loaded automatically on first launch and never written back to the app bundle.
