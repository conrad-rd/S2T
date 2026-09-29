# OpenRouter management key setup

## September 20 replacement account

The user clarified that the account replacement concerns the management credential that creates and manages other API keys. The earlier inference-key replacement alone did not satisfy that request.

- The new account was identified by its default inference key matching the user-supplied key.
- Created `S2T backend management` on the account's Management Keys page. OpenRouter identified it as management-only and showed it Active.
- Expiration: October 20, 2026 at 23:38 Europe/Berlin, retaining the earlier setup's 30-day lifetime.
- The user completed OpenRouter's login verification, then entered the generated key into the prepared Cloudflare rotation form and deployed it to the existing `OPENROUTER_MANAGEMENT_KEY` secret.
- Production Worker version `ab0ad39c-cfc6-4c6c-a919-800a3c06c8c8`, deployed at 100% on September 20 at 21:40:24 UTC. The script ETag, runtime and binding metadata match the previous version. Cloudflare displays the management secret as encrypted.
- Public database-backed health returned HTTP 200 with live mode. No child keys, billable model requests or real account-limit changes were used for verification. The stored secret cannot be read back, and an authenticated Management API call was not performed.

The one-time key was held in browser memory and redacted from tool output, then cleared from agent memory. It was not added to source or a local credential file. The user copied it for the Cloudflare handoff.

The earlier account's management key was not revoked. The new account's separate inference key remains configured for the current shared-request backend because management keys cannot perform inference. Automatic per-user OpenRouter provisioning and limit synchronization remain unfinished, as recorded in `direct-routing-plan.md`; changing this secret does not implement those features.

Reference: https://openrouter.ai/docs/guides/overview/auth/management-api-keys

## September 18 setup history

Completed September 18, 2026 with explicit user approval.

- Storage: the private Cloudflare account, Worker `s2t-credits`, encrypted secret `OPENROUTER_MANAGEMENT_KEY`.
- OpenRouter name: `S2T direct billing replacement`.
- Expiration: October 18, 2026 at 21:59 Europe/Berlin.
- The earlier `S2T direct billing` key was disabled after its one-time value appeared in browser tool output. Do not re-enable it.
- The replacement went directly from the provider's one-time display into Cloudflare's secret form through an in-memory browser variable. Credential-bearing observations were redacted. No clipboard, source file, shell argument, or local credential file was used.
- Verification: OpenRouter showed the replacement Active and the earlier key Disabled. Cloudflare showed `Secret / OPENROUTER_MANAGEMENT_KEY / Value encrypted` after saving.

This operation added a secret to the existing deployed Worker. It did not deploy local source, enable direct customer routing, issue customer keys, or make billable model requests. Direct routing still needs integration and verification. Newly managed keys do not inherit the existing shared inference key's spending allowance. Review their funding controls before enabling them. Rotate this server credential before expiry.
