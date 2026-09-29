# Dictionary observer recovery

The previous observer permanently exited on the first missing Accessibility sample or foreground change. Its isolated correction/controller checks did not exercise that lifecycle. A new production-watcher regression, with an actual NSTextView behind an injected Accessibility transport, reproduces the old failure: `A transient Accessibility failure permanently stopped the production correction watcher.`

The observer now pauses during an unavailable sample or focus change and resumes only in its original receiving field, within the existing one-minute deadline. Initial attachment can recover during that same deadline. A failed final validation requests a fresh evaluation instead of losing the correction permanently. Nonempty range text can also be read when an editor reports an empty Accessibility value. The latest status is persisted without field text.

Verification:

- `--verify-dictionary`: whole worker, native text edits, local file save, transient read failure, foreground leave/return, failed final validation, replacement, cancellation, provider-independent saving, secure/oversized exclusion, and confirmation controls pass.
- `--verify-dictionary-native`: separate native editor process, real Accessibility IPC, actual worker, and persisted `conrad → Konrad` entry pass. The generated window stays behind other windows; foreground identity is supplied for this background probe. No live provider, user dictionary, clipboard, or user editor is used.
- 34 focused dictionary core tests pass.

Evidence is in `build/dictionary-observer-20260926/`, including the failing original lifecycle, fixed checks, and packaged checks. A background-only WebKit experiment could not expose its focused field; it is not counted as browser coverage. The injected transport regression and real native editor test cover different layers, and neither asserts support for every external editor.

Focus changes no longer end observation immediately. Field content is still read only when the original app and original editor are focused; unrelated fields, secure fields, oversized content, expired sessions, and stopped sessions are not learned from. Existing surrounding-text and submitted-field guards remain in place.

Packaged as S2T 1.0.1 Build 905. Build identity, packaged dictionary probe and packaged real native-editor probe pass. Native save/hidden confirmation construction measured 7.0 ms; this excludes observer settling and does not measure provider inference. The older running process was preserved because repeated Computer Use calls to S2T timed out; quit and reopen S2T to load Build 905.
