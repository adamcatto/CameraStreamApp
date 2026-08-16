import assert from "node:assert/strict";
import test from "node:test";
import {
  defaultCaptureSettings,
  libcameraArguments,
  raspividArguments,
  sanitizeCaptureSettings,
} from "./capture-settings.js";

test("sanitizeCaptureSettings fills defaults and clamps out-of-range values", () => {
  const settings = sanitizeCaptureSettings({ gain: 999, brightness: -5, framerate: 30.6 });
  assert.equal(settings.gain, 64);
  assert.equal(settings.brightness, -1);
  assert.equal(settings.framerate, 31);
  assert.equal(settings.shutterMicroseconds, defaultCaptureSettings.shutterMicroseconds);
  assert.equal(settings.contrast, defaultCaptureSettings.contrast);
});

test("sanitizeCaptureSettings ignores non-numeric input", () => {
  const settings = sanitizeCaptureSettings({ gain: "high" as unknown as number });
  assert.equal(settings.gain, defaultCaptureSettings.gain);
});

test("libcameraArguments reflects the default pipeline", () => {
  const args = libcameraArguments(defaultCaptureSettings);
  assert.match(args, /--shutter 20000/);
  assert.match(args, /--gain 32/);
  assert.match(args, /--brightness 0\.2/);
  assert.match(args, /--framerate 30/);
  assert.match(args, /--codec h264/);
  assert.match(args, /--listen/);
});

test("libcameraArguments omits --shutter when set to auto", () => {
  const args = libcameraArguments(sanitizeCaptureSettings({ shutterMicroseconds: 0 }));
  assert.doesNotMatch(args, /--shutter/);
});

test("raspividArguments maps image controls onto raspivid scales", () => {
  const args = raspividArguments(defaultCaptureSettings);
  assert.match(args, /-ss 20000/);
  assert.match(args, /-fps 30/);
  // brightness 0.2 -> (0.2 + 1) * 50 = 60
  assert.match(args, /-br 60/);
  // contrast 1.0 -> (1 - 1) * 100 = 0
  assert.match(args, /-co 0/);
});
