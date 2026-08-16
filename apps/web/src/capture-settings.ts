// Client mirror of the gateway capture-settings contract, plus UI field
// metadata for the per-camera adjustment panel.

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

export interface CaptureField {
  key: keyof CaptureSettings;
  label: string;
  min: number;
  max: number;
  step: number;
  hint?: string;
}

export const captureFields: CaptureField[] = [
  { key: "shutterMicroseconds", label: "Shutter (µs)", min: 0, max: 200000, step: 500, hint: "0 = auto exposure" },
  { key: "gain", label: "Gain", min: 1, max: 64, step: 0.5 },
  { key: "brightness", label: "Brightness", min: -1, max: 1, step: 0.05 },
  { key: "contrast", label: "Contrast", min: 0, max: 2, step: 0.05 },
  { key: "saturation", label: "Saturation", min: 0, max: 2, step: 0.05 },
  { key: "sharpness", label: "Sharpness", min: 0, max: 2, step: 0.05 },
  { key: "ev", label: "EV compensation", min: -10, max: 10, step: 0.5 },
  { key: "framerate", label: "Frame rate", min: 1, max: 120, step: 1 },
];

const integerFields = new Set<keyof CaptureSettings>(["shutterMicroseconds", "framerate"]);

export function sanitizeCaptureSettings(value: Partial<CaptureSettings> | undefined): CaptureSettings {
  const result = { ...defaultCaptureSettings };
  for (const field of captureFields) {
    const candidate = value?.[field.key];
    let numeric = typeof candidate === "number" && Number.isFinite(candidate) ? candidate : result[field.key];
    numeric = Math.min(field.max, Math.max(field.min, numeric));
    result[field.key] = integerFields.has(field.key) ? Math.round(numeric) : numeric;
  }
  return result;
}
