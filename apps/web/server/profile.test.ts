import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadBundledProfile, sanitizeCredentials } from "./profile.js";

test("loadBundledProfile returns null when no profile files exist", async () => {
  const directory = await mkdtemp(join(tmpdir(), "camera-stream-profile-"));
  try {
    assert.equal(await loadBundledProfile(directory), null);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("loadBundledProfile reads workspaces and account credentials", async () => {
  const directory = await mkdtemp(join(tmpdir(), "camera-stream-profile-"));
  try {
    await writeFile(join(directory, "profiles-workspaces.json"), JSON.stringify([{ name: "Lab", cameras: [] }]));
    await writeFile(join(directory, "profiles-credentials.json"), JSON.stringify({ "pi@192.0.2.10": "secret" }));
    assert.deepEqual(await loadBundledProfile(directory), {
      workspaces: [{ name: "Lab", cameras: [] }],
      credentials: { "pi@192.0.2.10": "secret" },
    });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("loadBundledProfile rejects malformed JSON", async () => {
  const directory = await mkdtemp(join(tmpdir(), "camera-stream-profile-"));
  try {
    await writeFile(join(directory, "profiles-workspaces.json"), "{");
    await assert.rejects(loadBundledProfile(directory), /not valid JSON/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("sanitizeCredentials keeps only non-empty string passwords", () => {
  assert.deepEqual(sanitizeCredentials({ "pi@a": "x", "pi@b": "", "pi@c": 5, " ": "y" }), { "pi@a": "x" });
  assert.deepEqual(sanitizeCredentials(["pi@a"]), {});
});
