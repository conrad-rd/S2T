# Explicit model and endpoint selection

S2T 1.0.1, build 21, built 2026-09-12T21:30:50Z, was packaged, verified and restarted.

Removed the recommendation feed request, its decoder and app state, its menu and legacy settings controls. Existing selected model IDs are retained using their existing preference keys. The app no longer reads saved feed URLs.

OpenRouter remains the default processing provider. Its separate endpoint setting defaults to cerebras/fp16. Requests carry provider.only with that exact endpoint and allow_fallbacks=false. Other providers receive no endpoint default or OpenRouter routing object. Switching providers preserves each model and the OpenRouter endpoint. Explicitly clearing the endpoint stays cleared after restart. The chosen model must be supported on the endpoint. No live completion request was made.

58 service/domain tests passed, including independent scripted-request checks for the selected model, endpoint restriction, cleared endpoint and provider isolation. The packaged --verify-models check confirms menu metadata, legacy model retention, absent feed controls, default endpoint, persistence, provider switching and default reset. It does not open menus or access the clipboard, microphone or network. --verify-build confirms compiled identity, bundle metadata and menu label agree.

Logs are in build/verification/model-routing-tests.log, model-routing-menu.log, model-routing-identity.log and model-routing-package.log. Provider routing follows https://openrouter.ai/docs/guides/routing/provider-selection.
