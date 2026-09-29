# Key limits and sidebar credits

S2T 1.0.1 Build 595 at `build/S2T.app` places the credit balance in the persistent left rail directly above Policies. It bundles the supplied Bitcount Prop Single Regular font and OFL license. The number links to API keys; Manage limits opens `https://credits.s2t.app/#keys-details`. No user credentials were used for verification.

Account owners can create or edit a key with a credit cap, a lifetime/daily/three-day/custom reset interval and an optional expiry. Reset periods start at UTC midnight and retain their original anchor when settings are saved. Lifetime caps include all historical usage. Pending holds count across resets. Completed usage counts in the period in which its immutable debit was recorded. A reset renews only the key allowance, not the wallet balance. Expired and revoked keys cannot be revived.

The new `api_key_limits` table is additive. Existing keys have no additional cap. Existing key expiry is retained. Owner-only `POST /api/keys/limits` requires browser-origin validation, and checks key ownership. An app key cannot alter its limits. `GET /api/v1/balance` reports the calling key's allowance separately from account credits. Request reservations and submissions both enforce key policy.

## Verification

- `bash scripts/test.sh`: 319 tests passed, including backward-compatible balance decoding and recovery after key-limit errors.
- `npm test` in billing-local: 63 tests passed. New independent domain tests cover concurrent holds, daily/3-day/17-day resets, settlement across periods, lifetime limits, account isolation, atomic validation, terminal expiry and never-expiring keys.
- `npm run test:cloudflare`: working-source Durable Object integration passed with mocked external services.
- `node limits-deployment-check.mjs`: exact scoped production artifact passed authorization, CSRF, blocked dispatch, terminal expiry and restart/persistence checks, along with the existing payment and provider integration fixtures.
- `node browser-check.mjs` and `node key-limits-browser-check.mjs`: dashboard behavior, custom intervals, Enter submission, expiry, no-cap settings, unsaved drafts, revocation and 320/375/768/1280-point layouts passed in headless Chrome. No screenshots or clipboard access.
- `S2T_LIMITS_ASSETS='../build/limits-dashboard/public' node key-limits-browser-check.mjs`: same controls passed against the exact staged production files with isolated API state.
- Packaged `--verify-settings-sidebar`, `--verify-credits`, `--verify-build` and `node native-check.mjs`: passed with hidden windows, fake keys and synthetic audio. No screen capture or live provider requests.

## Deployment state

Cloudflare Worker version `00ff32ad-b8b1-4813-b709-19cad0e7e66d` is live. `build/s2t-limits-worker.js` was read back byte-for-byte, SHA-256 `8d2126049fb9fc607c107ed392a020211cd15d966c234b2239f051cfc580ff80`. Public health and configuration returned 200 in live mode. Its reviewed diff is `build/s2t-limits-worker.diff`. It preserves the existing account allowlist, secrets, provider pricing, assets and unrelated ledger behavior. Unpublished privacy maintenance is still excluded.

The limit controls are now live at https://credits.s2t.app/#keys-details. Vercel deployment `dpl_AGc8nWAoLhGBy5G5irT4MJwu2h6F` was prepared from fresh copies of all 15 current production assets and published using the authenticated account from an isolated directory. No Git author identity or access checks changed. This resolves the earlier `TEAM_ACCESS_REQUIRED` deployment failure.

The release adds the tested key-limit forms to the existing production layout, preserving the later copy, logo and policy changes. It also scrolls the app's Manage limits link to the controls after sign-in, clears key drafts on account changes, and explains that a service spending pause cannot be cleared by changing a key allowance. No service pause, user balance, key policy, provider budget or Worker configuration was changed.

The exact release is `/private/tmp/s2t-limits-publish-KONyq5`. Preparation and before/after asset hashes are in `build/limits-publish`. All 15 published assets matched the tested release byte-for-byte. Unauthenticated POST requests to the live limits endpoint returned 401.

Verification passed 64 billing tests, the scoped Worker artifact checks and the limit browser checks against both source and staged assets. The same browser flow passed against the published site with account API requests redirected to an isolated local ledger. It covers issuance, saving through Enter, daily/custom reset choices, reload persistence, draft preservation, expiry, no-cap settings, revocation, service pause messages, terminal expiry, link navigation and 320/375/768/1280-point layouts. No screenshots, real account edits, payments or provider inference were used. The native app was not changed for this website deployment.

The complete dashboard release `dpl_HhtuGXcS5DBeyNmZW1pqmeE7NBN5` supersedes the limits-only frontend deployment above. Key controls now live under the collapsed App connections section. The existing Manage limits URL opens that section after sign-in. The full limits browser flow passed against the new public dashboard with an isolated ledger. See `docs/verification/credits-dashboard.md`.
