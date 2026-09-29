# AssemblyAI direct customer access

Status: researched September 18, 2026. No message sent and no production routing change made.

## Required outcome

Audio travels directly from the native S2T app to AssemblyAI. S2T does not receive, relay, or store customer recordings. S2T funds transcription from customer credits and verifies billable usage independently of the client. Retain completed-file uploads, including recordings longer than two minutes, and preserve encrypted local recovery.

## Verified constraints

- AssemblyAI documents transcript and uploaded-file isolation per project, not per API key. PAYG currently lists two projects and four keys. Separate ordinary keys within one project do not establish customer isolation.
- The public Sync and prerecorded examples use ordinary API keys. No upload-only token, signed AssemblyAI upload URL, or scoped prerecorded client credential was found in the documentation reviewed. This is a documentation finding, not proof that AssemblyAI cannot offer the capability.
- Streaming supports temporary tokens with a bounded session duration. This is a different transcription product. Its client-reported termination duration is not independent billing evidence, and its transcript webhook sends content to S2T and can be configured by the client. Neither is sufficient by itself for the requested billing/privacy guarantees.
- Do not distribute the shared AssemblyAI key, automate undocumented dashboard APIs, switch providers, or introduce audio storage as a substitute.

Sources:
- https://www.assemblyai.com/docs/faq/how-to-get-your-api-key
- https://www.assemblyai.com/docs/streaming/api-spec/generate-streaming-token
- https://www.assemblyai.com/docs/streaming/webhooks
- https://www.assemblyai.com/docs/sync-stt/getting-started/quickstart

## Prepared support message

To: support@assemblyai.com

Subject: Direct native-app uploads with isolated customer credentials and usage billing

We are building S2T, a native macOS dictation app using AssemblyAI Sync for short recordings and prerecorded transcription for longer recordings. We need customer audio to travel directly from the app to AssemblyAI. Our servers must not receive, relay, or store recordings, and we cannot add an audio-storage or proxy service. We fund transcription through customer credits.

Do you support either short-lived, restricted credentials or signed upload URLs for direct uploads to /v2/upload and Sync? Ideally our backend would authorize a bounded request and receive only usage metadata afterward.

If that is unavailable, can we provision an isolated project/subaccount and API key per customer under centralized billing? We need documented provisioning and revocation APIs, customer data isolation, enforceable spending/product limits, and provider-side usage reporting by customer or credential. Your published PAYG limits of two projects and four keys appear insufficient. Is there a self-serve or startup option without an enterprise minimum commitment?

How can our backend independently verify billable duration and request ownership without receiving audio or transcript content, including requests where the app disconnects or does not report completion?

Streaming is a possible alternative, but would change our transcription model. If streaming is the only supported direct-client option, can temporary tokens bind permitted models/add-ons, an opaque customer/session identifier, and a server-controlled metadata-only billing callback or usage lookup? The client must not be able to remove billing attribution or forge usage.

Please provide the supported API contracts and pricing/plan requirements. We can adapt our integration, but direct app-to-AssemblyAI audio and isolated customer access are requirements.
