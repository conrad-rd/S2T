# Glow clarity

The user requested a crisp edge and smoother colored glow across Bottom, Around Notch and Around Input.

ChromaExpansion previously interpolated straight RGB and alpha independently. A generated red-to-transparent boundary reproduced darkening to red 0.6503 at alpha 0.2902. It now interpolates premultiplied half-float color and converts back to the bitmap's straight-alpha format. The independent regression checks both straight and premultiplied input and requires red above 0.98 throughout the sampled fade.

Rims and outward-distance fields use two samples per point. Body and native radius assets retain their existing resolution. Rendering remains on the existing asynchronous worker, with bounded caches.

The shared tuning adjustment sets edgeBlur to 0, edgeGlow to 0.5 and softness to 10. It preserves the background blur, falloff, color brightness, edge height and other stored appearance settings. The original tuning is backed up before applying the adjustment. This is a change to this user's saved tuning, not a reset of application defaults.

`--verify-glow-clarity` renders all three appearances from generated geometry and checks identical native maps before and after the tuning adjustment. Set `S2T_GENERATED_GLOW_FIXTURE_DIR` to export the authored comparisons. These are not screen captures and do not establish visual accuracy over live applications.

Validation commands:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
build/S2T.app/Contents/MacOS/S2T --verify-glow-clarity
build/S2T.app/Contents/MacOS/S2T --verify-brighter-edge
build/S2T.app/Contents/MacOS/S2T --verify-input-outline
build/S2T.app/Contents/MacOS/S2T --verify-notch
build/S2T.app/Contents/MacOS/S2T --verify-glow build/glow-clarity-native
build/S2T.app/Contents/MacOS/S2T --verify-appearance-performance
build/S2T.app/Contents/MacOS/S2T --verify-build
```

Version 1.0.1, Build 294 passed all 216 service/domain tests and every packaged check above, plus `--verify-gradient-cycle`. The notch check initially detected a foreground application change during user activity; the rerun passed. Color-reference errors remained within existing tolerances for all three modes. The native checks used hidden windows on both displays, and the generated comparisons were inspected without screen capture.

The responsiveness check measured maximum slider actions of 1.914 ms for Bottom, 3.884 ms for Notch and 5.973 ms for Input. The final generated fields arrived in 190, 80 and 864 ms respectively. Higher-resolution geometry still runs off the main thread. The saved tuning readback confirmed the three intended changes and the original backgroundBlur value of 0.14506880733944955. The existing S2T process was left running; reopening the canonical app loads the new binary and saved tuning.
