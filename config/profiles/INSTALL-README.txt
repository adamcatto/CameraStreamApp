Camera Stream ({{NAME}}) - install guide
========================================

These downloads come with the {{NAME}} camera workspaces and passwords already
loaded. Please don't share them outside the lab.

Before streaming, connect to the network or VPN that can reach the cameras.


macOS: CameraStream-{{SLUG}}-macOS.zip  (Apple Silicon only)
---------------------------------------------------------
The app runs only on Macs with Apple Silicon (M1 or newer), not on Intel Macs.
To check, open the Apple menu > About This Mac and look for "Chip: Apple M...".

1. Double-click the zip to extract it.
2. Open the "Camera Stream ({{NAME}})" folder and double-click
   "Install Camera Stream.command". It copies the app to Applications and opens it.
3. If macOS says the file can't be opened, open System Settings > Privacy & Security,
   scroll down, and click "Open Anyway" (on older macOS, right-click the installer
   and choose Open). You only need to do this once.


Windows: CameraStream-{{SLUG}}-Windows.zip
------------------------------------------
1. Right-click the zip and choose "Extract All...". Running the installer from
   inside the zip without extracting won't work.
2. In the extracted folder, double-click "Install Profiles Camera Stream.bat".
   It installs the app for your account and opens it.
3. If Windows shows "Windows protected your PC", click "More info" and then
   "Run anyway".


Linux: CameraStream-{{SLUG}}-Linux.zip  (64-bit Intel/AMD)
----------------------------------------------------------
1. Extract the zip.
2. In a terminal, in the extracted folder, run:
       ./"Install Camera Stream.sh"
   (Or right-click it in your file manager and choose "Run as a Program".)
3. Camera Stream opens in your web browser and appears in your applications
   menu. Nothing else needs to be installed, and no admin password is needed.
   To stop it, run: camera-stream --stop


Using the app
-------------
Pick a workspace on the left, then click "Start streaming" or "Open cluster shell".
You shouldn't be asked for a password.

The app loads the bundled workspaces only on its first launch. Installing a newer
download later won't replace workspaces that are already in the app.
