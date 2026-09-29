# Credits dashboard

The signed-in dashboard at https://credits.s2t.app uses the original S2T logo, Manrope controls and the app's Bitcount numerals. The usage chart uses short rounded strokes, with each day's height proportional to its actual credit usage. It sits directly on a near-black page, without a gradient card. Hover/focus uses a quiet lavender accent. Available credits and last activity sit above the chart. Activity, top-ups, keys and pricing are collapsed. Add credits opens a keyboard-accessible dialog. Credit action buttons contain text only, with no directional arrows.

The authenticated account endpoint accepts 7, 30 or 90 days. Totals aggregate all immutable usage debits, not the latest 20 request rows. Days are bucketed in UTC, include today and fill missing dates with zero. Last use is the most recent usage debit, independent of the selected period. Pending holds remain separate from usage. Provider totals and daily values use the same period. Top-ups, refunds and operator adjustments are not usage.

New requests optionally include a random installation UUID and a generic Mac model label. The app never sends its personal hostname. The ledger stores attribution alongside the original request inside the reservation transaction. Idempotent retries cannot replace it. Historical requests without metadata show Not recorded. Modern hardware with a generic model identifier is labeled Mac and distinguished by the final four characters of its installation ID. The app update must be reopened before new requests include this data.

The database change adds a metadata table and query indexes. It does not alter balances, payment rows or existing usage. Account authorization and the private email allowlist remain unchanged. No transcript or audio is included in analytics.

Verification passed 48 billing tests, the Cloudflare runtime test including persistence and cross-account isolation, responsive browser checks from 320 to 1280 pixels, chart keyboard navigation, Reduce Motion, top-ups, app-key management and pairing. Checkout browser tests use a mocked Stripe service and signed fixture webhooks. The Swift suite passed 308 tests. Packaged S2T 1.0.1 Build 573 passed build identity and credits integration checks with a mock transport. No real charge, microphone use, screen capture or credential extraction was used for verification.

Worker version: d6c6710a-50c5-4442-9435-741a5e5588c3. Production health/configuration and unauthenticated account denial were checked after deployment. Authenticated production analytics have not been read during this task; their aggregation and isolation were exercised with local and Cloudflare fixtures.

## Published dashboard, September 18

The complete dashboard is live at https://credits.s2t.app in Vercel deployment `dpl_HhtuGXcS5DBeyNmZW1pqmeE7NBN5`. The earlier author-metadata deployment block was resolved by publishing with the existing authenticated Vercel account from an isolated directory. No identity or access checks changed.

Available credits, last use and last device now appear above the 7/30/90-day UTC chart. Buying credits uses a keyboard-accessible dialog. Recent activity, top-ups, key settings and pricing start collapsed. The existing app Manage limits link expands key settings after sign-in. Credit balances, pending holds, settled activity, chart details and usage totals display exactly four decimals, including a one-micro-USD charge as 0.0001 credit.

The release uses the three canonical frontend files from billing-local/public and retains the published fonts, logo and six policy pages byte-for-byte. It changes no Worker code, budgets, account settings, keys, balances or native app package. The exact stage is `/private/tmp/s2t-dashboard-publish-hVoWmg`; preparation, reviewed JavaScript diff and before/after hashes are in `build/dashboard-publish`. All 15 public assets matched the verified stage after promotion. Unauthenticated 7/30/90-day analytics requests returned 401.

Verification passed 66 billing tests, the retained service artifact checks, and browser checks against staged and published assets. The public-site browser runs redirected all account requests to an isolated local ledger. Coverage includes chart periods, empty states, device attribution, four-decimal precision, 320/375/768/1280-point layouts, reduced motion, keyboard navigation, dialog dismissal/focus restoration, key creation and limits, direct links after synthetic sign-in, and clearing account data and the purchase dialog on sign-out. The mock Stripe browser check confirmed that checkout return alone grants no credit and duplicate signed events settle only once. No real account edits, payments, provider inference, screenshots or clipboard access were used.

## Brand refinement, September 18

Deployment `dpl_Dz9UkdjGZgmb2yf4D9HdvEHpzerp` supersedes the dashboard release above. The larger original logo retains its 70:29 proportions. Bitcount Prop Single Regular is bundled for balance and usage numerals with its OFL license. The page uses an asymmetric balance/activity layout, plain period tabs and a chart made from rounded horizontal strokes. Each day retains a linear amount-to-height mapping, and zero-use days draw no filled column. Keyboard navigation and exact four-decimal labels remain available. No decorative points or usage values are invented. Purchase arrows and the amount field's spinner arrows were removed.

The arrow regression first reproduced `Add credits ↗`, then passed against source, stage and the live site. The browser check covers demo/live purchase-button labels, all amount presets, bundled font loading, original logo proportions, a known 1:2:4 chart fixture, zero usage and hover details. Existing responsive, keyboard, account clearing, limits and mock checkout checks passed. All 66 billing tests passed. No screenshots, actual account edits or real payments were used.

The release stage is `/private/tmp/s2t-brand-dashboard-c9Mqwr`. Preparation, per-file diffs and before/after hashes are in `build/brand-dashboard-publish`. All 17 public assets matched the tested release, including the new font and license. Existing policy pages and Worker configuration were preserved. Native app files were not changed.

## Period selection, September 18

Deployment `dpl_8MQ21n8a9P9moPtw4y8LXcwh3Uh1` removes the selected period underline. Selected text uses full opacity, idle periods use 50 percent, and hovering an idle period raises it to 72 percent. Keyboard focus remains visible. This release changes only the selector CSS. Computed-style inspection confirmed no underline or pseudo-element, and the staged dashboard checks passed. All 17 production assets matched the tested stage at `/private/tmp/s2t-period-style-2MUzsQ`. Readback hashes are in `build/period-style-publish`.

## Purchase dialog and labels, September 18

Deployment `dpl_FvFHuBRCFVy9XCwpEe3ngtNxTWxS` removes the visible Credits header and Available credits label. The balance retains an accessible group name. The purchase dialog now leads with its Bitcount credit total, uses the page background, and has no outer border, internal rules or preset boxes. Presets use the same dimmed/selected opacity as the chart periods. Dollar input, amount bounds, legal links and the explicit purchase total remain intact.

Initial dialog focus goes to its title, avoiding the previous automatic outline around Close. Tabbing still shows keyboard focus, and Escape returns to Add credits. Computed-style and DOM inspection passed at 320/375/768/1280 pixels. Source, staged and public dashboard checks and mock Stripe checkout passed. All 17 published assets matched `/private/tmp/s2t-purchase-dialog-VFgAZY`; hashes are in `build/purchase-dialog-publish`. No real account edits, payments or screenshots were used.

## Chart axis and inline values, September 18

Deployment `dpl_By2Tbh6udXKdfuCVTXt8RfH2YQJb` replaces the bottom hover readout with a value beside the selected daily pillar and a thin connecting line. A vertical credit axis shows proportional four-decimal ticks. Zero-only periods show only zero; very small ranges avoid duplicate rounded ticks. Hover, click and keyboard focus expose the exact amount, UTC date and request count. Labels stay within chart bounds and disappear when focus and pointer leave. Sign-out clears the axis and detail.

Source, staged and published browser checks passed with isolated account data, including proportional 1:2:4 bars, keyboard navigation, focus dismissal, and first/last tooltip bounds at 320, 375, 768 and 1280 pixels. All 17 public assets matched `/private/tmp/s2t-chart-axis-DJGRa4`. Hashes and original production assets are under `build/chart-axis-publish`. The release excludes unrelated local balance-decimal styling and preserves production policies, fonts, Worker behavior and the native app. No screenshots, real account changes or payments were used.

## Balance decimals, September 18

Deployment `dpl_9j25g168hZwuVPqniLXxuN7BDtmF` renders the main balance's decimal point and four fractional digits at 50 percent opacity. Whole credits stay fully opaque, and the full text and precision remain intact. This scoped update was reapplied on top of the concurrent chart-axis publication before deployment. Computed-style checks covered normal, zero and one-micro-USD balances. The integrated staged dashboard checks passed, and all 17 production assets matched `/private/tmp/s2t-balance-decimals-zgljA8`. Evidence is in `build/balance-decimals-publish`.

## Chart footer cleanup, September 18

Deployment `dpl_73bFbqm1z4vTV5qsjvEBLVhH4vpk` removes the visible Days in UTC caption and the provider-summary top divider. UTC remains in the chart's accessible name. The staged browser checks passed, including explicit absence checks for the caption and divider. All 17 published assets matched `/private/tmp/s2t-chart-cleanup-NeZF3W`; records are in `build/chart-cleanup-publish`. The release applies only these HTML/CSS changes to the previous live assets.

## Cursor connector correction, September 18

Deployment `dpl_G8YPThKVQtpPB66YWHX2DXWDxqvD` connects the actual pointer position inside a visible pillar to its credit value. The value sits above and to the right or left with a 32-pixel gap. Pointer movement updates the line angle and length. Leaving the actual pillar, including moving into the unused portion of its button, immediately hides the value and line even after a click. The visible label contains only the credit amount. Keyboard focus retains an equivalent pillar-top connector, and full date/request information remains in the accessible button label.

Source, staged and live browser checks passed, including two pointer heights and dismissal after clicking a pillar. Responsive bounds and existing keyboard/account checks passed. All 17 published assets matched `/private/tmp/s2t-chart-cursor-PZCHoX`. Release records are in `build/chart-cursor-publish`. Live browser account requests used an isolated fixture ledger; no screenshots or real account edits were made.

## Pillar hover opacity, September 18

Deployment `dpl_D1mqHvLVH8xrQf6iPmBHx9tphDFB` sets idle pillars to 50 percent opacity and hovered or keyboard-focused pillars to full opacity. This is a scoped CSS release from current production assets at `/private/tmp/s2t-chart-opacity-QQjl13`. Staged and live browser checks passed using isolated account fixtures, including computed idle/active opacity. The retained release check in `build/chart-opacity-publish/browser-check.mjs` excludes concurrent, unpublished decimal-formatting assertions. Cursor connectors and immediate dismissal remain unchanged.

## Decimal formatting throughout the dashboard, September 18

All displayed credit and currency amounts now dim the decimal point and fractional digits to 50 percent opacity. This includes balance, usage, chart ticks and tooltips, provider totals, pending holds, activity, top-ups and reversals, key-limit summaries, purchase prices and pricing explanations. The formatter preserves full text and precision, while date strings and native numeric editing retain their existing behavior. Chart and provider selectors target direct children so nested decimal spans cannot inherit positioning or flex layout. Resizing dismisses an existing tooltip to prevent stale coordinates from overflowing the page.

The staged dashboard browser checks verify decimal opacity, inline layout, matching font sizes, exact text, one-micro-USD precision and 320/375/768/1280-pixel layouts. Key-limit browser checks and mocked Stripe checkout checks also pass. Existing concurrent chart cursor and hover changes are preserved. No real payments, real account edits or screenshots were used. Release files and asset hashes are in `build/all-decimals-publish`.

Published as `dpl_N8vYY9mQQYnRe3Crk18os6oQQ5qN` at `credits.s2t.app`. All 17 live assets matched `/private/tmp/s2t-all-decimals-kwAnU6`. The archived release browser check also passed against production with account requests redirected to the isolated local ledger. Its resize checks wait for the next animation frame before testing tooltip visibility. The archive excludes two assertions added concurrently for a later chart-color change, which is outside this release.

## Monochrome chart, September 18

The chart uses neutral gray for idle/active pillars, connector lines and keyboard focus. Hover changes opacity only, retaining the 50 percent idle setting and full opacity on hover. The release stage is `/private/tmp/s2t-chart-monochrome-aDE5YW`; staged browser checks passed with explicit neutral RGB assertions for active pillars and connectors. Account traffic used isolated fixtures. Remote-build deployment `dpl_DHSK8rSgb6rh2YuPgmb8gVuTj9gc` stalled during initialization. The same stage was built locally and published as prebuilt deployment `dpl_BwyC6a9bSZ9yYzCV9bda8obuGBX4`. Live browser checks passed, including neutral pillar/connector colors and opacity.
