import assert from "node:assert/strict";
import test from "node:test";
import { importCredentialDocument, importCredentialText } from "../src/credential-import.js";
import type { CameraWorkspace } from "../src/models.js";

const workspaces: CameraWorkspace[] = [{
  id: "workspace-1",
  name: "Example cluster",
  jumpHost: "rpicam@192.0.2.50",
  cameras: [
    { id: "camera-1", name: "Left", host: "192.0.2.10", username: "pi", port: 8888 },
    { id: "camera-2", name: "Right", host: "192.0.2.11", username: "pi", port: 8888 },
  ],
}];

test("imports an account-to-password JSON mapping", () => {
  const result = importCredentialDocument({
    "pi@192.0.2.10": "left-secret",
    "rpicam@192.0.2.50": "jump-secret",
  }, workspaces);
  assert.deepEqual(result.credentials, {
    "pi@192.0.2.10": "left-secret",
    "rpicam@192.0.2.50": "jump-secret",
  });
});

test("imports Kenny workspace credentials from YAML", async () => {
  const result = await importCredentialText(`
- workspaceName: Example cluster
  cameraPassword: camera-secret
  jumpPassword: jump-secret
`, "yaml", workspaces);
  assert.equal(result.importedAccounts.length, 3);
  assert.equal(result.credentials["pi@192.0.2.11"], "camera-secret");
  assert.equal(result.credentials["rpicam@192.0.2.50"], "jump-secret");
});

test("imports quoted CSV rows by account and by workspace", async () => {
  const result = await importCredentialText([
    "workspace,account,password,cameraPassword,jumpPassword",
    ',"pi@192.0.2.10","left,secret",,',
    '"Example cluster",,,shared-secret,jump-secret',
  ].join("\n"), "csv", workspaces);
  assert.equal(result.credentials["pi@192.0.2.10"], "shared-secret");
  assert.equal(result.credentials["pi@192.0.2.11"], "shared-secret");
  assert.equal(result.credentials["rpicam@192.0.2.50"], "jump-secret");
});

test("reports unmatched accounts without including passwords", () => {
  const result = importCredentialDocument({ "pi@192.0.2.99": "do-not-report-this" }, workspaces);
  assert.deepEqual(result.credentials, {});
  assert.match(result.unmatchedEntries[0] ?? "", /pi@192\.0\.2\.99/);
  assert.doesNotMatch(result.unmatchedEntries.join(" "), /do-not-report-this/);
});
