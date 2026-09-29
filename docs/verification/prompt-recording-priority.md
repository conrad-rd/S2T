# Prompt recording priority

September 26, 2026. The user reported lag throughout Prompt recording. The running app was Build 905. A passive process sample and CPU monitoring caught the app while idle; the user could not reproduce the lag during this session. Those samples do not identify its active bottleneck.

Continuous screen-frame encoding used a user-initiated dispatch queue and a Core Image context with normal GPU priority. It now uses utility CPU priority and Core Image's low-priority rendering option. Apple documents this option for background rendering that should yield to UI animations: https://developer.apple.com/documentation/coreimage/cicontextoption/priorityrequestlow

Explicit screenshot crops and thumbnail/PNG preparation retain user-initiated priority. Display coverage, four samples per second, capture resolution, pixel format, JPEG quality, memory limits, timestamps, screenshot placement and model requests are unchanged. This is a scheduling mitigation, not confirmation that the reported live lag has been reproduced or resolved.

Verification logs and the original recorder source are under `build/prompt-recording-lag`. The existing benchmark uses generated 2560×1440 display buffers; it does not capture screen contents, microphone audio, user fields or the real clipboard. Before the change, two display callbacks took a 7.362 ms median and 10.982 ms p95, retaining twelve expected frames. Displayed frame rate under live Prompt recording remains unmeasured.

Build 906 passed the existing full Prompt-mode probe, including generated frame freezing, full-display capture, rapid reference timing, screenshot delivery and cleanup fallback. The same generated encoding workload measured 7.834 ms median and 12.303 ms p95 after the change, retaining all twelve expected frames. This small encoding-time difference is not evidence of improved displayed FPS; both workloads remain below the 250 ms sampling interval. The changed scheduling makes UI work take precedence when resources are contested.
