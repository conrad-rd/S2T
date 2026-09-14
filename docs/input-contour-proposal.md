# Measure the input's visible border

This is a proposed replacement for estimating border shape from accessibility bounds. It needs permission to read screen pixels. The current implementation does not capture them.

## Data flow

1. Accessibility identifies the active editor and plausible enclosing containers. App names, website selectors, and per-app profiles are not inputs to the detector.
2. Analyze a small crop around those candidates in memory. Restrict it to the owning window and exclude secure inputs. Do not run OCR, save captures, upload pixels, or record a video.
3. Find consistent edges around the editor across several scan lines. Compare complete enclosing contours, including attachment and control regions. Reject page borders, nearby independent buttons, shadows mistaken for borders, and candidates that do not enclose the editor.
4. Fit each corner from the measured contour. Allow a rounded rectangle, capsule, or square border when the measurements support it. Use those measured curves for the gradient outline.
5. Cache the result for the same editor and layout. Recheck when geometry, appearance, or controls change. Rate-limit measurements during resizing. Keep all image processing off the main thread.
6. If the image does not provide a reliable contour, retain the accessibility fallback. Do not label an estimated curve as measured.

## Verification

Begin with synthetic light and dark input containers, varied radii, fractional placement, multiline growth, split controls, attachments, shadows and ambiguous backgrounds. Then verify real interfaces under the approved capture scope. Establish coverage from those results; do not claim a universal or 95% success rate in advance.

## Permission boundary

AGENTS.md currently says: "Never screen record, screenshot, or read back screen pixels to implement or verify this app."

The required exception is local, temporary pixel analysis for input-boundary detection and its verification. No application code may request screen-capture permission or read pixels before the user authorizes that exception. Accessibility-only behavior remains available when OS permission is absent or the user disables visual measurement.
