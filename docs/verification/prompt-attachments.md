# Prompt image clipboard repair

Reported behavior: T3 Code web received the prompt text without its images.

Multi-image delivery previously published only file URLs. PNG bytes were included only when there was exactly one screenshot. Every clipboard item now includes both its PNG payload and its saved file URL. The ordered batch, single paste request, output markers and existing cancellation, menu, foreground and clipboard guards are preserved.

The isolated attachment consumer now requires PNG bytes on every item. That check failed against the previous implementation with `Ordered automatic image paste with exact files`. The regression uses generated images, an isolated pasteboard and injected paste requests, without screen capture or user fields.

This verifies S2T's payload, not a browser's native clipboard conversion or T3 Code's acceptance of attachments. Live T3 Code attachment acceptance remains untested.

Evidence: build/prompt-attachment-before.log, build/prompt-attachment-tests.log and build/prompt-attachment-package-checks.log.
