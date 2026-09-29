# Volume pricing and legal-contact release

September 19, 2026. Canonical package S2T 1.0.1, Build 672, built 19:46:34 UTC.

Published:
- Credits frontend: dpl_BqMyExS9pnDQxyJmtYufzyLoXJbS at https://credits.s2t.app.
- Main site: dpl_9MPazscyZHCFZPRRFNuzKfEB9uAL at https://s2t.app.
- Worker: 72903fd0-af01-444f-addf-f40c1bc06590, SHA256 2ec29ecffc86b4b18183674244f4fc0beccb597acf926e148ab19ee7d971eef2.
- App executable SHA256 b5165321a389c052190d6cd39a790264e75f01d28c2f97f684d161a1d8a6b844.

New purchases grant 500/1,100/2,300/5,800/11,800 credits for $5/$10/$20/$50/$100. Custom cent amounts interpolate between anchors, rounded down to whole provider microdollars. All 9,501 allowed cent amounts preserve increasing grants and increasing value per dollar. Each credit remains 5,000 provider microdollars. Existing quote grants, balances and Stripe retry parameters are preserved. Refunds and won disputes use cumulative proportions of the original purchase grant. Full reversal is exact. Purchase history now uses actual grants.

The Impressum uses name/address/public support phone from the Stripe profile with explicit user authorization, plus the previously confirmed email. No tax identifier, register entry, legal company name or VAT exemption was invented. No active Stripe Tax registration was present. Tax collection and the private purchase allowlist remain unchanged. The Stripe business activity still needs updating before public sales.

The public withdrawal form requires no login. It records name, contact email, contract identification and an explicit browser-download delivery choice, with separate review and confirmation. It acknowledges only after a durable encrypted write and downloads a receipt containing the declaration and timestamp. Retries preserve the same receipt. It does not send email or issue a refund. Only the authenticated operator endpoint can list submissions. Download-only legal sufficiency, transactional email, operator notifications, durable purchase confirmations and registration/tax setup remain public-sales prerequisites. See docs/legal/OPERATIONS.md. A completed contact block is not legal certification.

Verification:
- 153 billing tests passed with local listeners enabled.
- The permanent release check passed against the exact Worker and packaged app. It includes build/credits verification, 34 billing regressions, the existing checkout/account/isolation suite, new volume/withdrawal runtime checks, and twelve native streaming-plus-cleanup cycles with three cancellations. Deliberately lost responses recover without duplicate charges or stranded holds.
- Exact Cloudflare runtime checked each tier, a non-integral-rate custom amount, partial/full refunds, funding totals, unauthenticated withdrawal submission, cross-origin denial, protected operator access, durable receipt replay and restart.
- Staged and published dashboard DOM checks used a separate local ledger for every API request. Verified tier previews, custom values, exact purchase credit/history, four viewport widths, two-step withdrawal and actual text-file download. No production payment or withdrawal was made.
- Staged and published main-site DOM checks preserved its current assets and exercised its preview tabs. Both sites' policy links and verified contact details passed. Six canonical static policy pages match between source destinations, have no scripts or third-party calls, and pass narrow viewport checks.
- After deployment, the live read-only health endpoint returned paused=false, incidents=[] and pending=[] at 19:52:50 UTC.

The Worker was patched from freshly downloaded production code, preserving live bindings and unrelated unpublished work. Deployment refused stale versions/settings, required the recorded release hash and compared the deployed bytes with the tested artifact. Site stages similarly started from published assets. No screenshots, real provider inference, microphone recordings, user clipboard or Raycast were used.

Artifacts: build/volume-pricing, including worker.diff, worker.js.verified.json, release-check.log, live-health.json and deployment logs. Tests are isolated; they do not establish future provider uptime or final legal compliance.
