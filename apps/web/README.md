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
