# Audio routing verification

The previous path used a persistent AVAudioEngine and opened its default input node before assigning the selected microphone. An empty microphone preference followed the macOS default, including Bluetooth headsets. The earlier device inventory included AirPods Max as the default microphone. The code never explicitly enabled voice processing. Apple's documented Bluetooth microphone behavior explains the reported reduction in playback quality.

The replacement uses input-only AUHAL capture. Output is disabled before assigning a device or initializing the audio unit. It preserves the hardware sample rate and buffer size. Stop, cancellation, and startup failures dispose the unit. Device removal and sample-rate changes end the capture and preserve the existing processing behavior.

Automatic selection now rejects Bluetooth and Bluetooth LE inputs, always prefers the built-in microphone when available, and fails visibly if no alternative exists. Explicit selections remain supported and never silently fall back when disconnected. Settings explain the playback tradeoff for an explicitly selected Bluetooth microphone.

The packaged release executable completed three automatic-input capture cycles on this Mac. Each 0.4-second cycle delivered 18,944 audio frames from MacBook Pro Microphone. The default output was MacBook Pro Speakers at 48,000 Hz with two channels. Its device ID, sample rate, and channel count stayed unchanged during and after all three cycles. The probe retains no audio and sends no network requests.

All 28 tests passed, including seven routing tests covering built-in preference over Bluetooth and wired system defaults, explicit headset and wired selections, no built-in input, disconnected selections, and Bluetooth-only availability. The native General settings were rendered from the packaged app for visual inspection.

A later check ran with AirPods Max connected as both the macOS default input and output. S2T's automatic route chose MacBook Pro Microphone. Three capture cycles received 18,944, 19,456, and 19,456 frames. The AirPods output device remained at 48,000 Hz with two channels before, during, and after all cycles. This verifies device routing and reported output format, not a subjective listening comparison. Explicit AirPods microphone capture was not tested. No live provider requests were made.

References: [Apple Bluetooth audio quality](https://support.apple.com/en-us/102217). The installed macOS SDK marks AVCaptureSession.configuresApplicationAudioSessionForBluetoothHighQualityRecording as iOS-only and unavailable on macOS, so that option is not used.
