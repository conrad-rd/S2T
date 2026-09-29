# Dictation responsiveness repair, September 25

The reported symptoms were a roughly 20-second delay after a one-minute dictation, lag across appearances, and loss of input focus **during recording**.

## Evidence and changes

The only surviving completed timing record, from 12:31:25 UTC, contains 189 words and 5.792 seconds from Finish to completion: transcription 2.491 seconds, cleanup 2.826 seconds, and insertion 0.319 seconds. The provider portions were 1.428 and 2.703 seconds. This does not establish the cause of the reported 20-second incident. No provider credentials, recordings, or transcript content were read or used for verification.

- Native Paste discovery previously bounded the number of Accessibility nodes but not elapsed time. It now has a shared 300-ms deadline, short per-read deadlines, and a bounded cache. The existing Unicode fallback remains available.
- Text-only delivery no longer waits 250 ms for a clipboard attachment handoff. Attachment delivery retains its wait. A destination already focused does not need another focus-restoration round trip.
- Focus restoration checks for intervening physical interaction, and all recording backdrop panels explicitly refuse key/main-window status. Nonactivation alone does not prohibit a panel from taking keyboard focus.
- Ordinary keyboard events and modifier flags bypass the main-thread wait in the global event tap. Shortcut interruptions remain ordered, including a fast Fn combination arriving before the main thread has handled Fn-down; configurable keys that can be consumed still receive a synchronous decision. Command-click only invokes Prompt handling while Prompt recording is active.
- Bitmap upload uses an exact byte/alpha-to-half-float lookup and avoids a full-size intermediate Float buffer. It does not reduce output resolution, alter colors, or lower blur quality.
- Settings refreshes coalesce, stop while the real settings window is hidden, and avoid rebuilding layout for elapsed-time or slider-value changes. Preview artwork is created only for the requested appearance and cached separately, rather than decoding every appearance on first access. A bounded source-image cache shares assets with the sidebar; loading bundled assets no longer also loads the development copies. Static preview layers defer Glur construction until they actually need a blur filter. Unchanged toolbar, sidebar-credit and menu-bar artwork and appearance properties are retained.
- A local history retains the latest 20 numeric timing records, including failed and cancelled work. It separates destination/menu waits, focus restoration and delivery from provider work. It stores no transcript, audio, credentials or field identities.

The required domain suite also exposed an existing source/test mismatch in DictionaryObservation. Its optional insertion-range initializer now supports the existing tests; callers that omit that argument retain their previous behavior. The native delivery fixture now enters the actual failed/retryable state before retrying and isolates all preview preferences. The older shared window probe now verifies the regular split-view item required by the September 24 full-width titlebar rule; table, selection and keyboard assertions remain in place.

## Measurements

Build 866 generated Within Input fields at 1900 × 1800 in 13.630 ms median and 15.546 ms p95. The last measured optimized package took 11.186 ms median and 14.658 ms p95, an 18% median reduction. The 1000 × 700 median changed from 4.351 to 3.868 ms. Generated output hashes were identical at both sizes. These are CPU field-generation measurements, not displayed frame rate or screen-pixel verification.

With an injected 80-ms main-thread stall, Build 876 measured ordinary key passthrough at 0.016–0.137 ms and an entire Fn combination at 0.022 ms. Synthetic shortcut tests cover ordered Fn combinations, hold/tap, capture, cancellation and Prompt separation. No keyboard events were posted during those checks.

`bash scripts/test.sh` passed all 459 service/domain tests. The startup probe measured 19–25 ms to recording with an injected 15-ms microphone startup, and 0.02–0.25 ms to requesting the appearance. Audio upload began only after Finish, preserved opening audio through the existing speech conversion, and correctly handled cancellation, failed transcription and delayed providers.

The resize probe passed: Within Input warm field generation averaged 6.87 ms; the changing-geometry scenario had a 1.04-ms maximum main-thread action and a 12.20-ms maximum timer interval. Generated mask and filter equivalence checks passed.

## Packaged verification

Delivered package: `build/S2T.app`, version **1.0.1, Build 876**. The existing Build 866 process was preserved.

- Passed the domain suite and packaged Prompt mode, onboarding, Paste batching, dictionary, glow, input outline, Within Input, settings sidebar, settings toolbar, menu highlights, resize performance, glass, notch and appearance-window checks during this repair. The final shortcut queue change passed the complete Prompt mode check in Build 876, including hidden WebKit rich/plain delivery and fake-provider success/failure flows.
- The actual native generated-editor fixture repeatedly retained editor focus through Bottom, Notch, Around Input and Within Input recording/processing phase changes. Native Start return, Finish destination restoration, full completion, cleanup-failure fallback, deferred menu delivery and Unicode/caret cases passed in individual runs.
- A complete uninterrupted native insertion matrix was not obtained: another foreground process interrupted runs. A PID-only observer established After Effects becoming foreground; the delivery guard correctly stopped instead of pasting into it. No real After Effects fields were read. One bezel run likewise stopped at its foreground-stability assertion after its geometry, generated blur, motion and hidden layout checks passed.
- The cold settings responsiveness check still fails its unchanged 50-ms timer threshold: the last measurement was 59.34 ms for the first interval, subsequent sampled intervals at most 15.30 ms, and slider actions at most 0.73 ms. This remains a first-layout limitation; it is not evidence that the reported sustained recording lag was reproduced. The threshold was not loosened.

## Limits

The exact reported slow recording and receiving-app focus loss have not been reproduced, so the changes do not establish the cause of the reported 20-second incident. Live AssemblyAI/Cerebras checks were not run because verification must not use real credentials. Physical Fn/emoji behavior requires a real user session. Verification uses generated audio, images, native editors, hidden windows, fake services and isolated pasteboards. It never captures the screen, inspects Raycast, records the microphone, or uses real provider credentials.
