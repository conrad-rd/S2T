# Provider key card

The API keys page now groups the processing provider picker, selected API key field, and save button in one card. AssemblyAI has a separate speech-to-text card with its own save button.

OpenRouter is the default when no provider has been saved. Existing Cerebras selections are preserved. Saving writes only the key belonging to that card and changes its button to a checkmark and Saved. Editing that key clears its confirmation. Keychain errors do not produce a saved confirmation. Preview verification uses synthetic keys in memory and does not write them to Keychain.

The packaged app builds and all 42 existing service and domain tests pass. Settings verification covers the default selection, provider switching, Save button action, saved confirmation, and clearing confirmation after editing. Window captures are under `build/verification/key-card-settings`.

This change does not alter dictation, clipboard, or paste behavior. No live provider request is needed for this settings change.
