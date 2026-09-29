# Classic website and checkout branding

The website has one Classic tab for floating Liquid Glass and attached Bezel, with Floating, Left and Right placement buttons. Existing native-derived preview assets remain in use. The first release used placement buttons to change forms. The follow-up in website-classic-drag.md adds continuous pointer and touch dragging, plus the current floating processing animation.

The main website, credits dashboard, withdrawal form and all policy pages use the original favicon at https://s2t.app/favicon.svg. The policy generator retains this reference.

The supplied Thank_you.png is copied byte-for-byte to the credits site's /stripe/thank-you.png asset. Only Stripe Checkout's per-session branding_settings.icon references it. Site favicons and page logos do not use it. The live Worker change is one additional checkout field; account branding, payment amounts, grants and ledger behavior are unchanged. Existing checkout sessions retain their original branding.

Verification artifacts are under build/website-classic. The production website build and TypeScript check pass. All 164 billing tests and the complete exact-Worker release gate pass, including synthetic native billing cycles, settlement, idempotency, isolation and storage maintenance. The additional exact-Worker fixture verifies checkout icon URL, amount, retry behavior and absence of a credit grant. No real Stripe request or payment was used. Stripe's connected app requires reauthentication, so publication uses the existing Cloudflare deployment authorization.

Published September 21, 2026:

- Main site dpl_BYfKJb48KU4VKygxVDaCoYFsrdi9, https://s2t.app.
- Credits dpl_YEZ7WwDdDUXddKW2rHxbG4uEgMMx, https://credits.s2t.app.
- Worker a7a827a7-6e8c-4813-9bb0-2cd97cd4d350. Deployed source readback matches SHA-256 aa3793e203496aba67e7c6793ed5929803c18d7c6640434d7211b02c12fd9f89.

The staged sites passed headless DOM checks at 320, 375, 768 and 1280 pixels, including placement buttons, Reset, keyboard navigation, all policy/favicon links, no horizontal overflow, and byte-identical checkout image delivery. No screenshots were taken. Native app source and the running app were unchanged.

The same DOM checks passed against both public domains after publication. The checkout image response matched the original PNG bytes. The Worker's public /health endpoint returned status ok, durable-sqlite storage and live mode. Stripe-hosted rendering was not inspected; checkout request contents were verified with an isolated mock transport and exact deployed-source readback.
