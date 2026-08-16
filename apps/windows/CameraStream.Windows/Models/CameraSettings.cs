using System;
using System.Collections.Generic;
using System.Globalization;

namespace CameraStream.Windows.Models
{
    // Per-camera encoder capture settings. The Raspberry Pi camera stack only
    // accepts these as launch arguments, so changing them means relaunching the
    // camera's encoder (see StreamController.ApplySettingsAsync). Defaults
    // reproduce the original hardcoded pipeline.
    public class CameraSettings
    {
        public int ShutterMicroseconds { get; set; } = 20000;
        public double Gain { get; set; } = 32;
        public double Brightness { get; set; } = 0.2;
        public double Contrast { get; set; } = 1;
        public double Saturation { get; set; } = 1;
        public double Sharpness { get; set; } = 1;
        public double Ev { get; set; } = 0;
        public int Framerate { get; set; } = 30;

        public static CameraSettings Default => new CameraSettings();

        public CameraSettings Clone() => new CameraSettings
        {
            ShutterMicroseconds = ShutterMicroseconds,
            Gain = Gain,
            Brightness = Brightness,
            Contrast = Contrast,
            Saturation = Saturation,
            Sharpness = Sharpness,
            Ev = Ev,
            Framerate = Framerate
        };

        public CameraSettings Clamped() => new CameraSettings
        {
            ShutterMicroseconds = Math.Clamp(ShutterMicroseconds, 0, 200000),
            Gain = Math.Clamp(Gain, 1, 64),
            Brightness = Math.Clamp(Brightness, -1, 1),
            Contrast = Math.Clamp(Contrast, 0, 2),
            Saturation = Math.Clamp(Saturation, 0, 2),
            Sharpness = Math.Clamp(Sharpness, 0, 2),
            Ev = Math.Clamp(Ev, -10, 10),
            Framerate = Math.Clamp(Framerate, 1, 120)
        };

        private static string Num(double value) => value.ToString("0.####", CultureInfo.InvariantCulture);

        // rpicam-vid / libcamera-vid capture arguments (excluding output).
        public string LibcameraArguments()
        {
            var s = Clamped();
            var parts = new List<string>();
            if (s.ShutterMicroseconds > 0) parts.Add($"--shutter {s.ShutterMicroseconds}");
            parts.Add($"--gain {Num(s.Gain)}");
            parts.Add($"--brightness {Num(s.Brightness)}");
            parts.Add($"--contrast {Num(s.Contrast)}");
            parts.Add($"--saturation {Num(s.Saturation)}");
            parts.Add($"--sharpness {Num(s.Sharpness)}");
            parts.Add($"--ev {Num(s.Ev)}");
            parts.Add("--width 1920 --height 1080 --codec h264");
            parts.Add($"--framerate {s.Framerate}");
            parts.Add("--autofocus-mode auto --lens-position 3 --inline --listen");
            return string.Join(" ", parts);
        }

        // Legacy raspivid capture arguments (excluding output), mapped from the
        // libcamera-centric scales onto raspivid's ranges.
        public string RaspividArguments()
        {
            var s = Clamped();
            static int ClampInt(double value, int low, int high) => Math.Clamp((int)Math.Round(value), low, high);
            var parts = new List<string> { "-md 4" };
            if (s.ShutterMicroseconds > 0) parts.Add($"-ss {s.ShutterMicroseconds}");
            parts.Add($"-ISO {ClampInt(s.Gain, 0, 1600)}");
            parts.Add("-w 1640 -h 1232");
            parts.Add($"-fps {s.Framerate}");
            parts.Add($"-br {ClampInt((s.Brightness + 1) * 50, 0, 100)}");
            parts.Add($"-co {ClampInt((s.Contrast - 1) * 100, -100, 100)}");
            parts.Add($"-sa {ClampInt((s.Saturation - 1) * 100, -100, 100)}");
            parts.Add($"-sh {ClampInt((s.Sharpness - 1) * 100, -100, 100)}");
            parts.Add($"-ev {ClampInt(s.Ev, -10, 10)}");
            parts.Add("-ih -n -l");
            return string.Join(" ", parts);
        }
    }
}
