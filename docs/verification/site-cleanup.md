# Website copy and policies, September 18, 2026

The header logo links to https://s2t.app/ on both sites and every policy page. The credits page uses Credits as its heading, removes its promotional subtitle and repeated balance explanation, hides routine live-mode badges and empty holds, shortens connection/key/payment instructions, and places pricing in a disclosure. Payment limits, purchase amounts, pending holds, status errors and test-mode notices remain visible when relevant.

Both footers link to Privacy, Terms, Refunds, Cookies and storage, Impressum and Security. Payment controls link to terms, withdrawal/refunds and privacy. The Impressum retains the existing legal.html URL, identifies the confirmed operator/email, and explicitly marks the missing address and applicable registration details as unfinished. All six pages remain temporary drafts. Update docs/legal/operator.json and docs/legal/policies.mjs, then run node scripts/build-policies.mjs to fill them out.

The published privacy text accurately distinguishes the live service from the prepared retention changes. It does not claim that rotating rate identifiers, expired-row removal or last-device-only retention are already deployed. No Worker, ledger, account, payment or provider configuration changed.

## Publication

The published sites were older than the local source. Isolated deployments retained the published JavaScript, styles and preview assets, applying only this task's changes. Pending dashboard charts/key-limit controls and unrelated main-site preview work remain unpublished. The source header, footer, policy generator and canonical dashboard copy also contain the corresponding changes for future builds.

- Credits deployment: dpl_3akBTG7EdkAqt1Xr1ZFen8zWsPm9, https://credits.s2t.app.
- Main site deployment: dpl_7YjSzA4X6Lk5rpYs11ASFN6Ah7SY, https://s2t.app.
- Exact staged copies: /private/tmp/s2t-site-cleanup-XTkfBD. Preparation and verification scripts are in build/site-cleanup.

Deploying from an isolated directory with the existing Vercel project binding succeeded using the authenticated account. No Git author identity was changed. This resolves the deployment mechanics, but does not mean previously staged key-limit controls have been published.

## Verification

All 63 billing tests passed. Existing dashboard and privacy browser checks passed with synthetic accounts. The main website production build passed. Exact staged pages passed headless DOM checks at 320, 375, 768 and 1280 pixels, actual intercepted home-logo navigation, all six policy links, the temporary Impressum, payment controls and disabled Clerk telemetry. No screenshots, real account access, provider inference or payments were used.

The canonical app packaging attempt stopped at the existing ModelsWindowProbe.swift:253 reference to SettingsFieldWell.glass, which is absent from the current type. The packaged app remains Build 598; its bundled policies have not been refreshed. The failed build's generated BuildIdentity was restored to the existing package metadata. No unrelated Swift code was changed to repair that failure.

The temporary Impressum is not a completed legal notice. The identity/contact requirements were checked against § 5 DDG, https://www.gesetze-im-internet.de/ddg/__5.html. Broader publication requirements remain in docs/legal/OPERATIONS.md.

Post-deployment checks also passed against both public domains, using fresh browser contexts and mocked sign-in/account responses. They verified actual logo-click navigation, all policy routes, responsive layouts, draft labels and all five existing main-site preview tabs without JavaScript errors.
