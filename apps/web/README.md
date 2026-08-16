# Web client

The browser port mirrors the native two-column workspace UI without requiring a
large application framework. A local Node process serves the TypeScript client
and performs the operations that browser security does not permit directly.

## Connection flow

For a workspace with a jump host, the gateway:

1. authenticates the jump host and keeps that SSH connection alive;
2. opens an SSH channel from the jump host to each camera independently;
3. starts the camera encoder on every reachable Raspberry Pi;
4. opens each raw H.264 TCP feed through the jump-host connection;
5. remuxes H.264 to fragmented MP4 with the locally installed FFmpeg binary;
6. streams the MP4 response to the browser on `127.0.0.1`.

Direct workspaces skip steps 1 and 2. A failed camera is listed as unavailable
and does not prevent the other feeds from starting.

## Live capture settings

Each live tile has an **Adjust** control that opens a per-camera panel for
shutter, gain, brightness, contrast, saturation, sharpness, EV compensation, and
frame rate. The Raspberry Pi camera stack accepts these only as launch
arguments, so **Apply** issues `PUT /api/sessions/:id/cameras/:cameraId/settings`,
which relaunches just that camera's encoder with the new arguments; the tile then
reconnects while the other feeds keep playing. Defaults reproduce the original
hardcoded pipeline, so streams look identical until a value is changed. Settings
are session-scoped and are not written to disk by the web client.

## Develop and run

From the repository root:

```sh
npm install
npm run web:dev
```

Open `http://127.0.0.1:4173`. To validate and run the optimized build:

```sh
npm run web:test
npm run web:build
npm run web:start
```

Set `CAMERA_STREAM_WEB_PORT` to choose a different loopback port.

## Data handling

Workspace definitions use browser local storage and can be imported/exported as
the shared JSON format. Passwords remain in JavaScript and gateway memory only
for the active session; they are not placed in local storage, output files, or
logs. Closing a session stops the remote encoders and SSH connections.

## Credential imports

The Settings screen and password prompt accept `.json`, `.yaml`, `.yml`,
`.csv`, `.tsv`, and `.xlsx` credential files. Parsing happens in the browser;
the source file is not uploaded or copied. Imported passwords populate the
session-only credential fields for accounts already present in a workspace.

Supported layouts include a direct account mapping:

```json
{
  "pi@192.0.2.10": "camera-password",
  "jump@192.0.2.50": "jump-password"
}
```

A workspace mapping can apply shared camera and jump-host passwords:

```yaml
- workspaceName: Example cluster
  cameraPassword: camera-password
  jumpPassword: jump-password
```

CSV, TSV, and XLSX files use a header row. They can identify a specific account:

```csv
account,password
pi@192.0.2.10,camera-password
```

Or assign shared values by workspace:

```csv
workspaceName,cameraPassword,jumpPassword
Example cluster,camera-password,jump-password
```

The importer also accepts `host` + `username` + `password`, and optional
`cameraName` for a camera within a named workspace. All XLSX worksheets are
read. Unknown accounts, workspaces, or cameras are reported but never created
implicitly, preventing a typo from silently attaching a password to the wrong
host. Credential files are limited to 10 MB. In spreadsheets, format passwords
as text when leading zeroes must be preserved.
