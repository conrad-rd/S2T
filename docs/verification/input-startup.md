# Input startup latency

The user reported about 300 ms before Around Input appeared after pressing the activation key.

The initial investigation measured a permitted geometry-only read of the current Helium input. The complete inspection process took 50 ms, including process launch. No field contents or screen pixels were read. The existing `--benchmark-appearance` workload took 892.62 ms to generate its first cold input field. These are separate measurements, not a physical key-to-display recording.

PreparedChromaGlow previously drew nothing until the complete color assets and native blur map were available. An independent generated first-frame test reproduced the blank output. The input window also used the shared 180 ms fade-in.

Around Input now draws a vector edge using the current contour and perimeter palette while its matching full frame prepares. It clips out the field interior and respects the edge visibility settings. Completed geometry replaces the temporary edge. A geometry change gets its new edge immediately rather than reusing the previous field. Full glow rendering, corner selection and native blur remain unchanged.

Input presentation now sets full window opacity immediately. Fade-out keeps its previous duration. A suppressed-presentation NSPanel verifies immediate opacity, hide/restart reversal and final cancellation without showing a window. Other appearance transitions retain their defaults.

`--verify-input-latency` checks circular rounded boxes, native continuous corners and capsules. It times first-frame output and full preparation for the identical request. It verifies exterior color before any prepared frame and zero alpha inside the field. All raster inspection uses generated fixtures, never live screen pixels. These timings do not prove physical key-to-display latency; fresh Accessibility lookup still precedes presentation.

Version 1.0.1, Build 301 passed all 218 domain/service tests and the packaged input-latency, input-outline, glow-clarity, glow and build-identity checks. For identical generated requests, initial edge/full preparation took 5.58/190.45 ms for rounded web corners, 0.41/180.43 ms for native corners, and 0.31/225.84 ms for capsules. Full preparation cost remains; it no longer blocks the first visible edge. Immediate window opacity took 0.01 ms in the suppressed-presentation test, and hide/restart/hide passed. The canonical app is build/S2T.app. The running app was not interrupted.

## Complete first frame

The extended Codex startup report exposed an unwanted sequence. Preparing the microphone selected the processing renderer. Recording then created the asynchronous listening renderer, which displayed a temporary vector stroke while building its full assets. Those separate presentations made startup appear to restart.

Around Input now keeps the listening renderer through microphone preparation and recording. The first visible listening frame contains completed color images and the native radius map together. The temporary stroke is removed. An obsolete empty render cannot replace a newer visible request. Transcription and cleanup retain their processing trails.

The fixed 1100 by 500 generated workload contains the recorded 736-point Codex body and its 710-point attached header, using the same speech settings before and after. Before the change, cold assets took 281.04 ms, color expansion 144.44 ms and the native map 9.99 ms, totalling 435.46 ms. Reusing the exact circular-boundary distance instead of computing a second power-based distance reduced total preparation to 299.24 and 348.78 ms in separate cold runs. Resolution, field shape and color/blur settings are unchanged. These timings measure generated preparation, not physical microphone/key-to-display latency.

The staged renderer regression blocks an initial empty job, submits visible work, then releases the old job. It asserts that no blank frame publishes and the first publication includes both color and native map. The color image is checked independently of the native bridge because SwiftUI ImageRenderer substitutes a placeholder for NSViewRepresentable. Hidden input-outline verification covers the native bridge, clear interiors, hosting and phase transitions. No screen capture is used.

Version 1.0.1, Build 324 passed the final staged startup, complete color/map, and hide/restart checks. Its cold Codex preparation measured 323.98 ms, compared with 435.46 ms before the change. The 231 service/domain tests passed. Generated contour checks passed in Build 322; input-outline and glow-clarity passed in Build 323 with the same production behavior. Build 324 changed only the diagnostic's color sampling to exclude the native-view placeholder.

## Rollback after the live drawing regression

The user reported severe flicker and roughly one FPS after Build 324. That invalidates the earlier startup result as evidence of acceptable live drawing. Build 326 restores the previous direct PreparedChromaGlow view, temporary startup edge, phase handling and distance calculation while retaining Codex/T3 targeting and compound outlines. The attempted startup fix is withdrawn; the original transition remains unresolved.

The replacement sustained check schedules 240 changing speech samples over four seconds instead of timing only cold asset preparation. Build 326 completed 235 frames, 58.74 generated frames per second, with a longest completion gap of 21.07 ms. It asserts at least 120 completions and no inter-frame gap over 100 ms. These are generated frame completions, not a measurement of presented screen frames, and do not independently reproduce the user's visible regression. The rollback removes the changes associated with that report.

All 231 service/domain tests, the compound contour checks, the recorded Codex and T3 reader checks and build identity passed. The canonical app is version 1.0.1, Build 326.


## Production-size lag investigation

The live thread sample showed repeated asset generation, image-channel conversion and GPU waits. S2T reported a 2.3 GB footprint and a 3.3 GB peak. The earlier 1100 by 500 fixture omitted the real 474-point panel padding and therefore did not reproduce the reported lag. Its 59 FPS result must not be treated as evidence that the live issue was fixed.

The corrected fixture uses InputOutlineGeometry for a 736 by 136 compound composer, producing a 1684 by 1084 panel. Before the cache fix it completed four frames in four seconds, with an 848 ms maximum gap. Both the four-sample rim assets and their half-float source texture exceeded the separate 96 MB cache budgets. They were evicted and rebuilt during continuous rendering.

The current working assets remain retained even when the bounded cache evicts them. Each immutable source image owns its source texture. Rendered images own shared Metal buffers through their Core Graphics data providers, eliminating per-frame bitmap readback and keeping storage alive through asynchronous drawing. Output uses premultiplied alpha, with half-float source filtering retained. A thin edge is rendered only at its requested expansion, rather than rendering and discarding an additional full-height edge. Contracted input fields skip sampling outside the source support and composer bounds. Panel geometry, four-sample rim resolution, palette and blur settings are unchanged.

Build 333 completed 200 default-setting frames and 206 thin-edge frames in four seconds, approximately 50 and 51.5 generated FPS including startup. Maximum completion gaps were 21.03 and 21.10 ms. These are frame-preparation measurements, not captured screen presentation rates. The thin-edge fixture uses explicit copies of the appearance values, never real preferences, microphone input or screen capture. The prior small Canvas timing experiment was removed because it did not measure the full production drawing workload.


Build 334 packages the same renderer and updates the alpha fixture to inspect its generated Core Graphics image rather than require a particular NSImage representation class. The shared image provider owns the buffer until its final drawing consumer releases it. The packaged glow clarity, input outline, compound contour, Codex/T3 fixture and build identity checks pass. All 231 service/domain tests passed. The canonical app was restarted from build/S2T.app. Live comparison remains pending the user's next visible outline.


## Startup stroke and moving blur, Build 342

The user reported a momentary full stroke before the completed glow and a subtle blur gap at each T3 footer join. The startup test reproduced the temporary stroke. A separate moving-map test reproduced 29 fully clear exterior samples next to the left footer join, despite those points needing blur coverage.

PreparedChromaGlow now waits for its completed color/map frame. Microphone preparation uses the same listening branch as recording, so that transition retains the renderer instead of briefly displaying processing trails. The asynchronous renderer and shared GPU buffers are unchanged.

Input blur assets now retain their field inside the input until expansion and frequency deformation finish. The final native map still clips the complete input interior. Both footer tests pass with bass and treble deformation at expansion 0.3, 0.55, 1.0 and 1.4. All 29 exterior samples per case retain 0.6 mask alpha, the configured transfer ceiling, while sampled input interiors remain zero. Bottom and Notch retain their existing intermediate-mask behavior.

Build 342 completes 196 frames in each four-second full-size workload, about 49 generated FPS including cold preparation. Longest completion gaps are 21.1 ms and 24.8 ms. Initial geometry fixtures remain transparent until the full frame is ready; their cold preparation takes 179–684 ms in this run. No physical key-to-display latency or displayed-screen FPS is claimed. All 231 service/domain tests, input-contour, input-outline, glow clarity and build identity checks pass. Verification uses generated pixels and hidden metadata only.

The packaged --verify-glow structural check also passed, including independent hidden-window hosting, phase persistence, fade reversal and Reduce Transparency. The canonical Build 342 app was restarted. Live appearance remains for user confirmation.
