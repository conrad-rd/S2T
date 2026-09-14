# Prompt mode repair

Verified package: S2T 1.0.1, Build 183.

The reported prompt contained six natural location references. The old detector required phrases such as "look here" and missed those cues. The regression now recognizes all six, including "like here", "zoomed in here" and "this tab here", while retaining negation and partial-result deduplication.

The saved image-model setting was openai/gpt-oss-120b. Its [public OpenRouter metadata](https://openrouter.ai/api/v1/models/openai/gpt-oss-120b/endpoints) declares text input only. The existing Gemini Flash default declares image input and text output. Model saving now checks those capabilities asynchronously, and image requests check them before sending a screenshot or credentials. Invalid selections retain the previous setting. Stale validation cannot save an edited value.

The original corruption was not reproduced in a simple hidden WebKit editor. Delivery now sends individual Unicode graphemes instead of 20-character typing packets. An independent chat-style Enter handler caught four accidental submissions when newlines were sent separately without Shift. Shift on newline events resolved that failure. The final generated 851-unit prompt arrives unchanged in both hidden WebKit rich and plain editors, including reference order, Unicode and line breaks, with zero submissions. These checks use the production event builder but dispatch locally to the fixture, never through the user's event stream.

Image-description failures retain the saved screenshot and put diagnostics in S2T, with only a short image reference in the delivered prompt. Automatic image attachment remains enabled. Live browser attachment acceptance and paid image-model requests were not tested.

All 175 domain/service tests passed. The packaged prompt-mode, menu, onboarding and build-identity checks passed. Logs are in build/prompt-repair-tests.log and build/prompt-repair-package-checks.log. No user browser state, screen pixels, microphone capture, real credentials, user fields or real clipboard were used in verification.
