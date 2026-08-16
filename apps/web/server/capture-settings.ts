// Canonical per-camera capture settings shared by the gateway launch command.
//
// The Raspberry Pi camera stack (rpicam-vid / libcamera-vid / raspivid) only
// accepts capture settings as launch arguments; there is no live control
// channel for a running encoder. Adjusting settings therefore means relaunching
// that camera's encoder with a new argument set (see SessionManager.applySettings).

export interface CaptureSettings {
  shutterMicroseconds: number;
  gain: number;
  brightness: number;
  contrast: number;
  saturation: number;
  sharpness: number;
  ev: number;
  framerate: number;
}

export const defaultCaptureSettings: CaptureSettings = {
  shutterMicroseconds: 20000,
  gain: 32,
  brightness: 0.2,
  contrast: 1,
  saturation: 1,
  sharpness: 1,
  ev: 0,
  framerate: 30,
};

interface FieldBounds {
  min: number;
  max: number;
  integer?: boolean;
}

const bounds: Record<keyof CaptureSettings, FieldBounds> = {
  shutterMicroseconds: { min: 0, max: 200000, integer: true },
  gain: { min: 1, max: 64 },
  brightness: { min: -1, max: 1 },
  contrast: { min: 0, max: 2 },
  saturation: { min: 0, max: 2 },
  sharpness: { min: 0, max: 2 },
  ev: { min: -10, max: 10 },
  framerate: { min: 1, max: 120, integer: true },
};

function clampField(field: keyof CaptureSettings, value: unknown): number {
  const fallback = defaultCaptureSettings[field];
  const numeric = typeof value === "number" && Number.isFinite(value) ? value : fallback;
  const { min, max, integer } = bounds[field];
  const clamped = Math.min(max, Math.max(min, numeric));
  return integer ? Math.round(clamped) : clamped;
}

/** Coerce arbitrary input into a complete, in-range CaptureSettings object. */
export function sanitizeCaptureSettings(value: unknown): CaptureSettings {
  const raw = (value && typeof value === "object" ? value : {}) as Partial<CaptureSettings>;
  return {
    shutterMicroseconds: clampField("shutterMicroseconds", raw.shutterMicroseconds),
    gain: clampField("gain", raw.gain),
    brightness: clampField("brightness", raw.brightness),
    contrast: clampField("contrast", raw.contrast),
    saturation: clampField("saturation", raw.saturation),
    sharpness: clampField("sharpness", raw.sharpness),
    ev: clampField("ev", raw.ev),
    framerate: clampField("framerate", raw.framerate),
  };
}

/** Format a number for a shell argument without a locale or trailing zeros. */
function num(value: number): string {
  return Number.parseFloat(value.toFixed(4)).toString();
}

/** Build rpicam-vid / libcamera-vid capture arguments (excluding output). */
export function libcameraArguments(settings: CaptureSettings): string {
  const parts: string[] = [];
  if (settings.shutterMicroseconds > 0) parts.push(`--shutter ${settings.shutterMicroseconds}`);
  parts.push(
    `--gain ${num(settings.gain)}`,
    `--brightness ${num(settings.brightness)}`,
    `--contrast ${num(settings.contrast)}`,
    `--saturation ${num(settings.saturation)}`,
    `--sharpness ${num(settings.sharpness)}`,
    `--ev ${num(settings.ev)}`,
    `--width 1920 --height 1080 --codec h264`,
    `--framerate ${settings.framerate}`,
    `--autofocus-mode auto --lens-position 3 --inline --listen`,
  );
  return parts.join(" ");
}

function clampInt(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, Math.round(value)));
}

/** Build legacy raspivid capture arguments (excluding output). Image controls
 * are mapped from the libcamera-centric scales onto raspivid's ranges. */
export function raspividArguments(settings: CaptureSettings): string {
  const parts = ["-md 4"];
  if (settings.shutterMicroseconds > 0) parts.push(`-ss ${settings.shutterMicroseconds}`);
  parts.push(
    `-ISO ${clampInt(settings.gain, 0, 1600)}`,
    `-w 1640 -h 1232`,
    `-fps ${settings.framerate}`,
    `-br ${clampInt((settings.brightness + 1) * 50, 0, 100)}`,
    `-co ${clampInt((settings.contrast - 1) * 100, -100, 100)}`,
    `-sa ${clampInt((settings.saturation - 1) * 100, -100, 100)}`,
    `-sh ${clampInt((settings.sharpness - 1) * 100, -100, 100)}`,
    `-ev ${clampInt(settings.ev, -10, 10)}`,
    `-ih -n -l`,
  );
  return parts.join(" ");
}
