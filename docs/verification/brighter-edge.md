# Brighter edge

The user selected variation E for Bottom, Around Notch, and Around Input from `studies/appearance-reference/index.html`.

`BrighterEdgeStyle` ports that preview's field formulas and four-color palettes, including its 1.08 light multiplier, 1.35 edge multiplier, and pale Bottom lift. The original preview images and renderer are preserved. The old Chroma JSON presets remain unchanged as historical references.

The app adapts the field to its existing geometry. Bottom uses the preview's distance units directly. Around Input scales distances and the 18-unit native blur radius by outline width divided by 940, bounded to 0.25 through 1. Around Notch uses housing width divided by 411.25 and a 12-unit native radius. Its centered fallback maps the whole strip to the reference width. These adaptations preserve the real input and hardware boundaries. The reference's white input body, black top backing, and artwork are scenery and are not drawn over the user's apps.

The diffuse color and edge compose to the preview's maximum of halo and rim coverage. The edge stays attached while the diffuse field deforms with speech. Listening uses sRGB composition to match the study. Processing indicators keep their previous drawing and timing.

Intensity, Width, Minimum amount, and Maximum amount retain their bindings, saved values, ranges, and speech response. The approved appearance is the nominal 100-percent field; the controls continue scaling it. Around Input still ignores Width, and Bezel still hides the glow amount controls. No Bezel source changes were made.

Color and native maps still render together through the background queue. A newer request replaces queued work. Generation skips transparent padding without changing the visible fields. Native blur uses the existing WindowServer sampler. No image of the desktop is read.

Verification compares the production Canvas and native mask to frozen E PNG samples at nominal gain. It also checks submitted filter radii and clear interiors. Sampling differences are bounded for raster interpolation; this is generated-fixture verification, not a claim of screen-pixel or cross-app visual parity. Live microphone and provider requests are unnecessary for this appearance change and were not used.

## Results

Packaged and verified S2T 1.0.1 Build 192 at the canonical `build/S2T.app` location. All 184 domain/service tests passed. Preview matching, slider persistence/ranges, notch fit and lifecycle, input targeting and lifecycle, native glow composition on both displays, Bezel, menu metadata, and build identity checks passed. Bezel source hashes match the pre-change baseline.

The production Canvas differed from the approved E samples by at most 1.14 levels out of 255 in premultiplied color. The native maps differed by at most one level. The reference-size filters submitted 12 points for Bottom and Notch, and 18 for Input.

The same five maximum-amount slider changes were measured before and after in an isolated preview process. Each run started with cold geometry caches. These are controlled preparation timings, not live display latency.

| Mode | Before, newest field ready | After, newest field ready | After, slowest slider action |
| --- | ---: | ---: | ---: |
| Bottom | 182 ms | 155 ms | 0.482 ms |
| Around Notch | 333 ms | 88 ms | 0.475 ms |
| Around Input | 775 ms | 663 ms | 0.500 ms |

The main run loop's longest interval on a five-millisecond timer was 7.18 ms after the change. Cached speech rendering, cancellation/restart, zero amount, and equality between prepared and synchronous Canvas output passed. Cold input geometry still takes longer than the other modes, but it stays off the main thread.

Commands:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
build/S2T.app/Contents/MacOS/S2T --verify-brighter-edge
build/S2T.app/Contents/MacOS/S2T --verify-appearance-performance
build/S2T.app/Contents/MacOS/S2T --verify-appearance-sliders
build/S2T.app/Contents/MacOS/S2T --verify-notch-fit
build/S2T.app/Contents/MacOS/S2T --verify-notch
build/S2T.app/Contents/MacOS/S2T --verify-input-outline
build/S2T.app/Contents/MacOS/S2T --verify-glow build/glow-verification
build/S2T.app/Contents/MacOS/S2T --verify-bezel
build/S2T.app/Contents/MacOS/S2T --verify-menu-highlights
build/S2T.app/Contents/MacOS/S2T --verify-build
```
