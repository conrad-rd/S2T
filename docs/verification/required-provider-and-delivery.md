# Required provider and transcript delivery

Verified on September 12, 2026 using the packaged macOS app.

The previous pipeline skipped both clipboard and paste when text processing threw an error. A live editor regression test reproduced this with a missing processing key. Existing successful-paste tests passed in the same run. Evidence is in `build/verification/processing-failure-before.log`.

The app now requires an explicit OpenRouter or Cerebras selection and both the AssemblyAI and selected processing provider keys before recording. No provider is selected by default. Settings shows only the selected processing provider key field and preserves separate saved provider settings.

Transcription copies its result before processing begins. Final delivery copies and verifies the clipboard before checking paste permissions or returning from S2T to the previous app, then sends Command-V. Processing errors deliver the original transcript and show an error. No field lookup or AX text mutation is used for delivery.

Verification:

- All 42 service and domain tests passed.
- All 17 live editor checks passed, including selection replacement, native search, return from S2T, old disabled paste preference, missing processing key, and five simulated responses for each processing provider.
- Provider response cases cover success, rejected key, exhausted credits, timeout, and incomplete output. These use synthetic recordings and injected HTTP responses through AppState and DictationAPI. They verify the clipboard before processing finishes and the final clipboard and selected editor text afterward.
- Required selection, conditional key fields, Cerebras readiness without an OpenRouter key, sidebar navigation, native slider, and glass Preview button passed in the packaged settings window.
- Real window captures are in `build/verification/required-provider-settings`. The unselected state shows neither segment selected, and selecting Cerebras reveals its key field.

Logs are in `build/verification/processing-failure-after.log`, `required-provider-tests.log`, and `required-provider-settings.log`. One intervening attempt aborted when the editor lost focus. The successful rerun followed the user's explicit instruction to run the check with the keyboard and mouse untouched.

Provider responses in this verification were simulated. No live AssemblyAI, OpenRouter, or Cerebras request was made in this change. No Raycast interaction was used. Tests restore the previous clipboard if it still contains their own data.
