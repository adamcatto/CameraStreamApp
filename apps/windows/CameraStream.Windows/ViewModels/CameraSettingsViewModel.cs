using System;
using CameraStream.Windows.Models;

namespace CameraStream.Windows.ViewModels
{
    // Slider-friendly view over CameraSettings. All values are exposed as
    // doubles for two-way binding; integer fields are rounded in ToModel().
    public class CameraSettingsViewModel : ObservableObject
    {
        private double _shutter;
        private double _gain;
        private double _brightness;
        private double _contrast;
        private double _saturation;
        private double _sharpness;
        private double _ev;
        private double _framerate;

        public CameraSettingsViewModel(CameraSettings settings)
        {
            CopyFrom(settings);
        }

        public double Shutter { get => _shutter; set => SetProperty(ref _shutter, value); }
        public double Gain { get => _gain; set => SetProperty(ref _gain, value); }
        public double Brightness { get => _brightness; set => SetProperty(ref _brightness, value); }
        public double Contrast { get => _contrast; set => SetProperty(ref _contrast, value); }
        public double Saturation { get => _saturation; set => SetProperty(ref _saturation, value); }
        public double Sharpness { get => _sharpness; set => SetProperty(ref _sharpness, value); }
        public double Ev { get => _ev; set => SetProperty(ref _ev, value); }
        public double Framerate { get => _framerate; set => SetProperty(ref _framerate, value); }

        public void CopyFrom(CameraSettings settings)
        {
            Shutter = settings.ShutterMicroseconds;
            Gain = settings.Gain;
            Brightness = settings.Brightness;
            Contrast = settings.Contrast;
            Saturation = settings.Saturation;
            Sharpness = settings.Sharpness;
            Ev = settings.Ev;
            Framerate = settings.Framerate;
        }

        public CameraSettings ToModel() => new CameraSettings
        {
            ShutterMicroseconds = (int)Math.Round(Shutter),
            Gain = Gain,
            Brightness = Brightness,
            Contrast = Contrast,
            Saturation = Saturation,
            Sharpness = Sharpness,
            Ev = Ev,
            Framerate = (int)Math.Round(Framerate)
        }.Clamped();
    }
}
