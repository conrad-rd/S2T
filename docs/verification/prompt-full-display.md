# Entire-display prompt capture

Prompt capture now uses the display filter with an empty excluded-window list. It excludes no applications, including S2T, and includes the menu bar. Startup checks the native filter's display scope and full display dimensions before creating a stream. Capture never uses the destination app or a window as its source.

The previous code already requested a display, but excluded S2T. Metadata from the latest user-generated references showed 1800 × 1169 PNGs. Only file headers and sizes were inspected, never screen pixels. This does not establish what those images showed or fully reproduce the reported failure.

A generated 96 × 64 desktop contains two independently changing rectangular windows and a background visible around every edge. The production recording encoder retains the full fixture at both timestamps. The session selector and PNG writer must preserve both complete frames. The fixture also uses a display with a negative horizontal origin.

The fixture compares decoded image components directly, avoiding a device-color-space conversion that changes grayscale numbers independently of capture geometry.

Checks use generated pixels, isolated storage, fake providers and injected events. Live screen recording remains untested and was not invoked. Evidence is in build/prompt-full-display-tests.log and build/prompt-full-display-package-checks.log.
