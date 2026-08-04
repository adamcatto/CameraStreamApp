import assert from "node:assert/strict";
import test from "node:test";
import { parseSshTarget, validateSessionRequest } from "./models.js";

test("parseSshTarget supports the shared user@host format", () => {
  assert.deepEqual(parseSshTarget("rpicam@192.0.2.50"), {
    account: "rpicam@192.0.2.50",
    host: "192.0.2.50",
    port: 22,
    username: "rpicam",
  });
});

test("validateSessionRequest applies the stream-port default", () => {
  const request = validateSessionRequest({
    workspace: {
      id: "workspace-1",
      name: "Lab",
      cameras: [{ id: "camera-1", name: "Camera 1", host: "192.0.2.1", username: "pi" }],
    },
    credentials: { "pi@192.0.2.1": "secret" },
  });

  assert.equal(request.workspace.cameras[0]?.port, 8888);
  assert.equal(request.startEncoders, true);
});

test("validateSessionRequest rejects unsafe hosts", () => {
  assert.throws(() => validateSessionRequest({
    workspace: {
      id: "workspace-1",
      name: "Lab",
      cameras: [{ id: "camera-1", name: "Camera 1", host: "host; reboot", username: "pi" }],
    },
    credentials: {},
  }), /invalid host/);
});
