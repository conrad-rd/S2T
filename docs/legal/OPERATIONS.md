# Policy maintenance and privacy operations

Conrad Baulig confirmed his name and info@conrad-baulig.com for publication. On September 19 he authorized using his Stripe legal profile. Its individual/company address is Boisseréestraße 1, 50674 Köln, Deutschland, and its public support phone is +4915123203112. operator.json now contains those details. Stripe contains no active tax registrations. On September 19 the operator explicitly confirmed that he has no VAT ID, Wirtschafts-Identifikationsnummer or Handelsregister entry. Omit these identifiers from the Impressum unless subsequently assigned. This does not establish a VAT exemption. Do not invent identifiers or publish a personal Steuernummer. He also confirmed that S2T has no transactional email service yet. Confirmation emails and operator notifications remain unconfigured. Completing these contact details is not certification that public sales are legally ready.

Edit policies.mjs and operator.json, then choose every output explicitly. Generate the canonical credits pages with `node scripts/build-policies.mjs --release --destination billing-local/public/policies`. A separate website checkout needs its own explicit destination, for example `--destination /absolute/path/to/website/public/policies`; repeat the option when one reviewed run should update both destinations. Release mode refuses publication preparation without an address. The native packaging script generates policies directly in its clean app staging directory and does not change either website tree. Footer links and checkout links point at these pages. The credits deployment script copies the canonical public assets into a clean deployment stage.

The pages contain no scripts, remote fonts or tracking. The only third-party request caused by opening a policy is the website host connection itself. The app has one small Policies link at the bottom of its settings sidebar. It opens the bundled privacy page, whose navigation reaches all six policies. There is no policies menu command or submenu.

## Before public sales

These drafts describe the inspected implementation. They do not certify legal compliance. Confirm the operator's establishment and sales countries, business address, any required register/VAT details and applicable national consumer requirements with qualified counsel. Do not invent registration details or promise worldwide compliance.

Confirm the required retention schedule for invoices, accounting and dispute evidence. The current immutable ledger has no archival expiry; the privacy notice says so. Implement a legally justified archival/pseudonymisation procedure before records are retained longer than needed. Preserve balances, duplicate-payment protection and unresolved liabilities.

Verify actual Vercel, Cloudflare, Clerk, Stripe and AI account settings, processor agreements, subprocessors, processing regions, transfer safeguards, recovery-copy retention and provider training choices. Source configuration cannot prove hosted account settings. Set the shortest available operational log retention. Keep request bodies, authorization headers, audio, transcripts, images and personal hostnames out of logs. Cloudflare observability is disabled; Clerk SDK telemetry is explicitly disabled.

The refund policy preserves statutory withdrawal rights. Valid statutory withdrawal within the applicable period receives a full reimbursement because checkout currently collects no separate early-performance request. Do not deduct consumed credits from those reimbursements. Outside statutory withdrawal, unused paid credit is calculated from the original purchase grant including volume bonuses, actual usage and prior refunds. No $5 block becomes nonrefundable merely because usage starts.

The public withdrawal form at credits.s2t.app/withdraw.html accepts declarations without sign-in, even when an account is frozen or providers are paused. It asks for name, email and contract identification, has a separate confirmation action, and transmits a timestamped text file after confirmed durable storage. The consumer explicitly chooses the browser download as their confirmation medium. It does not send email or issue refunds automatically. Declarations and receipts are encrypted in the ledger, with retry identity and an operator-only inbox. Legal review of the download delivery mechanism under BGB §§ 356a and 126b remains outstanding. A transactional email service, automated operator notification and durable purchase-contract confirmations are still needed before public sales. The existing private allowlist must remain in place.

The authenticated operator API action `withdrawals` retrieves the most recent 100 receipt records. This is currently a manual inbox, not an alerting system. The operator must review requests and meet applicable refund deadlines. Configure and test reliable notification delivery before relying on this for public customers. Keep request content out of logs. Do not run verification submissions against the production inbox.

If S2T processes personal data for business customers as their processor, assess and provide an Article 28 data-processing agreement. A generic public privacy policy does not replace one. Do not advertise business data-processing compliance before the contract and provider terms are in place.

## Active-database retention

| Data | Purpose | Handling |
| --- | --- | --- |
| Raw audio and request body | Requested transcription or cleanup | Processed in memory by the gateway; not stored as ledger inputs |
| Encrypted result text | Recover response after a network interruption without charging again | One-hour availability; cleanup every minute, including idle Cloudflare alarms |
| Pairing code and encrypted-key derivation link | Connect the app to the signed-in account | Expires at ten minutes; next cleanup removes link |
| Local preview session | Preview sign-in | Seven-day expiry; next cleanup removes session |
| Rate identifier | Bound abuse without storing raw IP/account/key identifiers in rate rows | Window-scoped HMAC, expires at the end of its one-minute or one-hour window; next cleanup removes row |
| Installation ID and generic Mac label | Last-device display | Cleanup retains pending requests and the latest completed usage per account; no device history, personal hostname or historical inference |
| Payment, usage and audit metadata | Balance, charge reconciliation, refunds, fraud and legal records | Immutable; archival schedule still needs operator/legal confirmation |
| Clipboard text | Optional reference matching | Opt-in for new installs; local encrypted history of 50 entries for 48 hours; preserve existing choices and files |
| Reference images, prompts, dictionary, local models | User-selected app features | Local user files; no deletion or observation of real files in verification |

Cleanup removes expired ciphertext from the active database, not necessarily SQLite journals, Cloudflare recovery versions or provider storage. Do not promise immediate physical erasure. Deployment of the maintenance code would clear already-expired transient records on startup. This task tests that only in isolated databases, never against the real ledger.

## Rights and security requests

Monitor the public email. Record only a request ID, request type, received date, response deadline and outcome in a restricted operator record. Verify ownership through the existing account or receipt where possible. Do not ask for an identity document by default. Keep any evidence only as long as necessary for the request and applicable claims.

For access, provide the person's account and payment/usage records without another account's data. Local clipboard contents and local files are not available from the S2T server. Explain any retained accounting records and legal basis when closing an account. Coordinate Clerk/Stripe/provider deletion separately as applicable; revoking an app key is not account erasure. Do not alter the immutable ledger through ad hoc SQL.

For suspected breaches, stop unnecessary access, preserve limited relevant evidence, assess affected data and severity, and follow applicable notification deadlines. GDPR Article 33 can require notification to the authority within 72 hours of awareness; Article 34 can require notice to affected people when risk is high. Ask for safe reproduction evidence, not real credentials or other users' data.

## Sources reviewed

- [GDPR text, including Articles 28, 33 and 34](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng), processor agreements and breach handling.
- [European Commission GDPR principles](https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations/principles-gdpr_en), data minimisation, purpose and retention.
- [Your Europe contract information](https://europa.eu/youreurope/citizens/consumers/shopping/contract-information/index_en.htm), trader identity and pre-contract information.
- [Your Europe withdrawal rights](https://europa.eu/youreurope/citizens/consumers/shopping/returns/index_en.htm), withdrawal and exceptions.
- [European Commission online consumer protection](https://commission.europa.eu/digital-life/protecting-you-when-buying-online_en), online withdrawal function.
- [Clerk telemetry controls](https://clerk.com/docs/guides/how-clerk-works/security/clerk-telemetry), telemetry: false in Clerk.load.
- [OpenRouter data policy controls](https://openrouter.ai/docs/guides/features/zdr), endpoint policies and why data_collection deny is not a universal zero-retention promise.

## Verification

Run billing-local's `npm test`, `npm run test:cloudflare`, `node browser-check.mjs`, and `node privacy-browser-check.mjs`. The privacy tests exercise expiry, retry identity, money preservation, raw-IP exclusion, window rotation and legacy schema migration. Run `npm run build:vercel` in website. Run `bash scripts/test.sh` and `bash scripts/build-app.sh`, then the canonical app's `--verify-build` and `--verify-clipboard`. Use no real payments, user fields, credentials, microphone or screen capture.

## September 18 temporary publication

The user requested policy links and a temporary Impressum to fill out later. Both websites now publish the six clearly marked drafts. The legal notice is titled Impressum and retains legal.html. The business address and any applicable register/VAT details remain unfinished. Do not present these drafts as completed compliance documents. The current published privacy text explicitly records that the hosted retention improvements have not been deployed. See docs/verification/site-cleanup.md for the scoped deployments and verification.

## September 19 pricing and legal-contact release

The new quote version is volume-2026-09-19. Orders snapshot the exact provider-value grant. Migration preserves previously quoted grants and legacy retry parameters. Each credit remains $0.005 of provider usage. Price anchors are $5/500, $10/1,100, $20/2,300, $50/5,800 and $100/11,800; intermediate cent amounts interpolate between anchors. Partial reversals use cumulative proportional integer rounding, and a full reversal removes the exact original grant.

Tax collection remains unchanged and no exemption has been asserted. Registration, tax classification, invoice setup, confirmation delivery and the earlier data-protection operational requirements remain public-sales prerequisites. The Stripe profile still describes motion design/video editing and cnrd.one; update the business activity and public support profile to include S2T before public sales. Do not mistake enabled Stripe charges for confirmation of tax or registration compliance.

See docs/verification/volume-pricing.md for the release artifacts and checks.
