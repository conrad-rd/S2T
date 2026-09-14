# Speech amplitude response

Bottom, Around Notch and Around Input use a shared envelope relative to the selected intensity. Listening silence is 30 percent. Maximum microphone volume is 200 percent. The existing 0.7-power microphone response and short attack/release smoothing connect the endpoints. The Chroma JSON exports remain the nominal baseline.

The envelope scales brightness, exterior distance and native blur together. It never scales the physical notch or input path. Processing retains its existing indicator and disables the live blur. Reduce Motion holds field size at the selected nominal level and removes frequency deformation while retaining brightness response. Bezel keeps its existing renderer, meter response and blur.

ChromaExpansion caches geometry vectors and source textures. A Metal compute pass resamples the existing fields outward from their boundary; the three color layers share one command submission. The final color and blur retain their existing exterior clips and frequency transform. This uses only generated textures, never desktop capture.

Verification uses core endpoint/monotonicity tests, authored Canvas images, generated stripe filters, synthetic microphone levels and hidden windows. SpeechEnvelopeProbe compares silence, medium and loud output in all three renderers. ChromaProbe checks 30 percent quiet blur, 200 percent loud blur, processing shutdown and the exact submitted map. Existing notch/input geometry and bezel checks remain active. Cross-app visual appearance and physical microphone response are not asserted by these checks.

In the same 30-frame synthetic mask workload, the initial Core Image implementation took 15.93 ms for notch and 14.42 ms for input after warming geometry. The Metal implementation's initial check took 4.85 ms and 2.71 ms respectively. These are mask-generation timings, not end-to-end frame rates. Final packaged timings are recorded in build/speech-envelope-frames.log.

Final package: S2T 1.0.1, Build 170. All 167 core/service tests passed. The packaged --verify-glow, --verify-notch, --verify-input-outline, --verify-bezel, --verify-contour-frames, --verify-menu-highlights and --verify-build checks passed. Final warm native-mask timings were 4.83 ms for notch and 2.46 ms for input, compared with 1.69 ms and 2.00 ms for their unexpanded baselines in the same workload. Both attached displays passed the hidden-window checks. No live microphone or screen capture was used.
