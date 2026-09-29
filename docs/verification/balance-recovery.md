# Balance warning recovery, September 20

The production billing service was healthy at `2026-09-20T14:25:23.659Z`. Its operator health request returned HTTP 200, `paused:false`, no open incidents and no pending requests. This is a point-in-time database check, not a live provider request or an uptime guarantee. No support message was sent.

## Reproduction and repair

`AppState.refreshCredits()` marked a temporary balance failure as a key issue without allowing another refresh. Its own entry guard then skipped all subsequent refreshes, even after the server recovered. The saved connection and recording access remained available, but the balance and key warning stayed stale.

A regression fixture first injects HTTP 503, then restores a successful balance response. The original app failed with `Recovered billing service is blocked by a stale balance warning after failure 503`. The same fixture covers an offline network error, successful recovery, preservation of recording access and saved credentials, and a rejected credential that must still require explicit validation.

Refresh failures now use the existing `CreditAccountError.automaticallyRefreshable` classification. Other transport and service failures allow a later refresh. Account errors keep their existing restrictions. Key revision checks still discard responses for replaced credentials. Existing refresh triggers include opening settings and completing credit-funded dictation; this change does not add a polling loop.

The native verification also now opens the existing Advanced settings disclosure before checking its model editor. It checks the compact primary model choices separately, matching the current Models hierarchy without changing the interface.

## Verification

The 400 service and domain tests passed after the repair. Canonical S2T 1.0.1 Build 689, compiled `2026-09-20T14:26:12Z`, passed the packaged credits, model and build checks. Its executable SHA-256 is `7e394c0fb92e9a7b964f31289e830995ee3d0588a244d96bcb3d25377f11b73f`. The final verification includes newer concurrent interface work and was run under the existing packaging lock.

The exact deployed Worker remains version `5cc9cca5-6690-4c6c-b27b-9fb901acef05`, SHA-256 `889882c866ec2e8f4863e0f0a5c50f2f486cd03b2a4b597977f06c1d5f71c8b5`. No new Worker deployment was needed. Its release check passed 164 billing tests, the existing exact-artifact regressions, isolated purchases/refunds, storage maintenance checks, twelve complete packaged streaming-plus-cleanup cycles, and deliberately lost successful authorization, cancellation and completion responses. Provider requests, payments and audio were simulated. No live inference, real recording or screen capture was used.

The follow-up production check at `2026-09-20T14:26:56.094Z` again returned HTTP 200, spending enabled and no pending requests or open incidents. Evidence is stored in `build/balance-recovery`, including the failing baseline, final release log and artifact hashes. Provider refill automation and continuous operational alerts remain unresolved as recorded in `storage-quota-recovery.md`.
