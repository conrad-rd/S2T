# Direct provider routing plan

Definition of done: supported hosted requests send their content only from the native app to the selected provider. The billing server sees authorization metadata and provider-reported cost, preserves account/key limits and immutable debits, and can reconcile usage after client disconnects without releasing uncertain funding. Shared provider and management keys never reach the app. Existing provider choices and recording recovery remain intact.

Tasks:
- [x] Read the operating principles and ground current routing and accounting.
- [x] Verify provider authorization and usage API contracts against primary documentation.
- [ ] Resolve delegated-budget accounting and provider enforcement gaps before implementing live spending.
- [ ] Build fake-provider checks for content bypass, account isolation, duplicate completion, disconnect, unknown create outcome and late usage.
- [ ] Implement durable backend authorization and reconciliation.
- [ ] Integrate native direct requests and recording recovery without fallback through the billing server after direct authorization.
- [ ] Run service, native, packaged and provider-configuration checks; update the canonical app.

Known constraints: OpenRouter requires a management key and verified key-level restrictions. Its keys are not single-use and documented usage fields have no finality marker. AssemblyAI documents client temporary tokens for streaming, not the existing prerecorded upload/Sync endpoints. Switching to streaming would change the selected product and requires an explicit product decision. No existing shared key may be sent to the app.
