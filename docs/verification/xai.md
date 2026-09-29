# xAI and Grok

Text cleanup supports direct xAI keys with `grok-4.6` as the initial model. The xAI key uses its own credentials-v1 vault entry and read-only `/v1/models` validation. Model preferences are independent of OpenRouter. Direct requests use `https://api.x.ai/v1/chat/completions` without OpenRouter host or routing settings. Dictation offers `grok-voice-transcribe-2.0` and `grok-voice-transcribe-1.0`, defaulting to 2.0. It uses the same xAI key, independent personal and subscription speech-model preferences, and the multipart `https://api.x.ai/v1/stt` endpoint after recording finishes. The model field precedes the WAV file. Native word timestamps are retained. No xAI streaming connection is opened.

S2T credits has a separate xAI service choice. The app sends the S2T connection key only to the configured billing service. The service sends `XAI_API_KEY` only to xAI. Missing service configuration is shown in Settings. The production xAI route is not enabled yet because no service key or reviewed funding settings have been supplied.

## Enable subscription access

Create a dedicated API key in https://console.x.ai and configure its funding and spending controls. Do not paste the key into chat or source files. From `billing-local`, store it using `npx wrangler secret put XAI_API_KEY`, which prompts for the value.

Add an xai entry to the existing S2T_PROVIDER_LIMITS_JSON only after reviewing actual funding controls. Preserve existing entries and account allowlists. The configuration requires prepaid funding or a recorded cap of at most $20, `autoRecharge: false`, and an evidence description of at least 20 characters. Do not invent evidence or imply that a provider alert is a hard cap.

Merge this route into S2T_PRICING_JSON and update the policy version after verifying current model pricing:

```json
"xai:cleanup": {
  "model": "grok-4.6",
  "title": "Grok 4.6",
  "inputMicrosPerToken": 2,
  "outputMicrosPerToken": 6,
  "maxOutputTokens": 2048,
  "maxInputBytes": 16000,
  "maxRequestMicros": 100000,
  "feeBps": 0
}
```

These are reservation ceilings. Settlement uses xAI's `usage.cost_in_usd_ticks`, rounded up to the ledger's microdollar precision. Missing cost or receipt data cannot become a successful charge. Incomplete output with a valid receipt settles the charge and reports a failed cleanup, preserving original-text delivery. Definitive rejection releases its hold. Existing uncertain-charge and overrun rules remain active.

Deploy the worker only after the key, policy, and funding configuration are ready. Refresh the S2T key in the app to retrieve its live model catalog. A Grok consumer subscription does not configure the API integration.

## Verification

- `bash scripts/test.sh` includes XAITests for separate credentials, requests, key errors and S2T routing.
- `cd billing-local && npm test` includes xai.test.mjs for exact billed cost, reservations, idempotency, rejected requests and incomplete cleanup.
- Packaged `--verify-api-keys`, `--verify-local-models`, `--verify-credits`, `--verify-models-window`, and `--verify-build` exercise hidden native controls and isolated fixtures.
- No live xAI inference, payments, real keys, microphone input or screen capture is needed by these checks.

Sources checked September 19, 2026: https://docs.x.ai/developers/models/grok-4.6 and https://docs.x.ai/developers/cost-tracking.

## Speech subscription route

Enable this additional route only after the same xAI service key and reviewed funding controls are configured. Both speech models use the documented REST rate of $0.10 per hour, checked September 19, 2026. The client retains the existing bounded upload partitioning and recovery behavior.

```json
"xai:transcription": {
  "model": "grok-voice-transcribe-2.0",
  "title": "Grok Voice Transcribe 2.0",
  "microsPerSecond": 28,
  "microsPerHour": 100000,
  "maxSeconds": 120,
  "maxRequestMicros": 10000,
  "feeBps": 0,
  "alternatives": [{
    "model": "grok-voice-transcribe-1.0",
    "title": "Grok Voice Transcribe 1.0",
    "microsPerSecond": 28,
    "microsPerHour": 100000,
    "maxSeconds": 120,
    "maxRequestMicros": 10000,
    "feeBps": 0
  }]
}
```

Speech responses report duration rather than the chat endpoint's billed-cost ticks. Settlement uses the returned two-decimal duration and the reviewed hourly rate, rounded up to a microdollar. The duration must match the uploaded PCM duration within 0.02 seconds. Missing duration or provider receipt prevents settlement. Live service access remains unverified without credentials.

Sources: https://docs.x.ai/developers/model-capabilities/audio/speech-to-text and https://docs.x.ai/developers/models/speech-to-text.
