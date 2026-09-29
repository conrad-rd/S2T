# Guest prepaid keys

`credits.s2t.app/prepaid.html` sells one prepaid key without Clerk sign-in. The existing signed-in account dashboard and its email allowlist remain intact. `S2T_GUEST_CHECKOUT=enabled` explicitly opens guest sales. Real-provider staging configurations with an account allowlist reject this flag.

Stripe Checkout uses the existing amount validation, volume pricing, idempotent orders, signed webhook verification, immutable grants, refunds and dispute handling. Redirects alone cannot credit a purchase. Verified payment creates one key per guest wallet. Retries and recovery return that same key, including after its balance reaches zero; revocation never issues a replacement. Guest keys have no practical scheduled expiry. Normal account key issuance and device-pair approval reject guest wallets.

A Secure, HttpOnly, SameSite=Lax, host-only cookie grants browser access for 180 days. The database stores its hash. It authenticates only guest routes, never account-management endpoints. The key is derived with a purpose-specific HMAC from the existing result encryption secret and wallet identity. Preserve that secret when deploying. A separate HMAC recovery code can restore browser access; its stored hash is independent of the app key. The user can download the key and recovery code. They must save the code before paying if they do not want to rely on the browser or optional email.

Email recovery is optional and unchecked by default. It is offered only when both `S2T_RECOVERY_EMAIL_KEY` and `S2T_RECOVERY_EMAIL_FROM` exist. The current adapter uses Resend and needs a verified sending address. Configure the API key as a Worker secret, never in source. Configure the sender as a Worker secret or variable. No real recovery email was sent during implementation.

Only the email returned by a verified paid Stripe session is eligible, and only for a wallet that opted in. The address is encrypted with AES-GCM and an account-bound associated-data value; lookup uses a keyed hash. Requests return the same generic message for unknown addresses, opted-out purchases and delivery failures. Per-IP and per-address limits restrict sends. Recovery links contain a random secret in the URL fragment, expire after 15 minutes and work once. The page removes the fragment and exchanges it by a same-origin POST. The email contains no app key. Mail redirects are not followed.

Guest sales can be disabled without disabling existing keys, sessions or recovery. Browser sessions and email links enforce expiry at lookup. Guest purchase/recovery rows currently have no automatic archival expiry. No changes are required in the Mac app; the result is a standard S2T app key.

## Verification

- `npm test` in `billing-local` passed 171 tests, including the new guest ledger, Stripe and recovery tests.
- `npm run test:guest` bundles the actual Worker, runs it in Miniflare with durable SQLite and drives the real guest page in headless Chrome. Stripe, Resend and external requests are intercepted. It checks payment gating, repeated webhooks, one-key issuance, account isolation, CSRF, cookie persistence, optional email, saved-code recovery, single-use email recovery, recovery within an already open page, and restart with sales disabled.
- `node cloudflare-check.mjs` passed the existing Worker regressions.
- No real payments, emails, AI requests, screen capture or user clipboard reads occur in these checks. The browser test reads DOM state, not pixels. A real paid guest purchase and actual mailbox delivery remain untested.

Email sender configuration is still required before the optional email control can appear in production.

## Published September 21, 2026

Worker version `a7c87e00-6388-4e24-a8fd-86ce65eb3810` and Vercel deployment `dpl_97QqSW6gak3PSLAA4vaUCc57A8Cw` are live. The user chose to launch with recovery codes and leave email recovery disabled. Production checks matched the page, scripts, stylesheet and privacy notice byte-for-byte with the tested source. `/api/config` reports guest checkout enabled and email recovery disabled. Ledger health is OK. Unauthenticated account, key-management and guest-status requests are rejected; cross-origin guest creation is rejected. The check created no live wallet or payment. Evidence is in `build/guest-production-check.json`.

Vercel blocked the initial repository-based deployment before building. Publishing the same tested static files from an isolated folder with the existing authenticated Vercel account succeeded. No account ownership, project membership or access restrictions were changed. No native app changes or rebuild were needed for this web-only feature.

## Homepage button correction

The main homepage now has a Buy prepaid key link beside Credits. Both use the existing `.credits-link` style, including typography, padding, rounded corners and hover treatment. The credits homepage uses its existing `primary compact` button style for the same action. No new button design was introduced.

Homepage deployment `dpl_DmZSvxW4RHppA2DMwfPfKH7vXQR3` and credits deployment `dpl_7W5ZFawcR7FDcE4WSW1uP6nYfXVq` are live. The site build passes. Local and live headless DOM checks verify identical header-button styling, nonoverlapping layout at 320/375/768/1280 pixels, keyboard activation and the prepaid destination. The credits index matches published source byte-for-byte. No screenshots, payments or live guest wallets were created. Verification script: `build/guest-homepage/verify.mjs`.

## Prepaid page design correction

The prepaid page now follows the homepage's black background, 64-point logo, Manrope type and rounded white selected controls. Bitcount remains limited to credit figures and custom amounts. Presets use the same pill shape, font weight and selected colors as the homepage appearance controls. The main layout separates the short heading from the purchase controls, with one payment button. Custom amount, recovery-code backup and lost-key recovery are collapsed initially. Recovery codes remain available before payment and the download includes the key after payment. Optional email remains disabled in production.

Published as `dpl_9ubZEwpt3oetpY6hoV6LbLvXCMho`. The actual Worker/browser flow passes payment, recovery and responsive preset checks. `build/prepaid-design-check.mjs` compares the live controls' computed font, weight, rounding and colors with the homepage, verifies disclosures and preset pricing at 320/375/768/1280 pixels, and matches published assets byte-for-byte. It intercepts guest API calls with fixtures, so no production wallet or payment is created. No screenshots were used; these checks verify DOM layout and behavior, not pixel-level appearance.
