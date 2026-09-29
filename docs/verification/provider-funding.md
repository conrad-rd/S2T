# Credit margin, provider funding and refunds

September 19, 2026.

New purchases retain 20% of the payment before fees and fund provider usage with 80%. $1 still buys 100 credits; one credit represents 8,000 provider-cost microdollars. OpenRouter funding fees and payment processing fees reduce the margin. This is not a net-profit guarantee.

Historical ledger entries remain immutable. Existing provider-dollar balances, holds and key-budget amounts retain their value; their credit display increases by 12.5% under the new conversion. Refunds derive the reversal rate from the original purchase entry, so old purchases still reverse 9,000 microdollars per paid cent and new purchases reverse 8,000. Replayed payments and refunds remain idempotent.

## Funding plan

The authenticated operator action `funding` reports a 70% OpenRouter and 30% AssemblyAI allocation within the provider budget. A $20 purchase allocates $11.20 and $4.80, with a $4 service margin before fees. These are accounting allocations, not transfers or segregated bank balances.

Provider funding accrues only from settled paid usage. Per-account calculations exclude unused balances, pending holds and complimentary credit usage. Whole $5 provider-funding batches accrue separately for each provider after applying the 70/30 ratio. Returned `cumulativeBatchedMicros` is a cumulative accounting amount, not a new transfer instruction. Never repeatedly transfer that total. No executor, transfer receipts or automatic top-ups are implemented; the response explicitly has `transfersAutomated: false` and `availableForPayout: null`.

Do not use the reported margin as a payout allowance. Stripe fees, refunds, disputes, payout delays and initial provider float still need cash coverage. Both providers require an existing funded balance before serving requests. A fixed 70/30 funding ratio can differ from actual consumption and cannot guarantee provider availability. Provider card auto-top-ups would not enforce this usage-earned batching rule, so they were not enabled.

Actual automated replenishment remains unfinished. It needs a supported payment integration for both providers, an initial cash buffer, transfer receipts and idempotency, and reconciliation with Stripe net settlements and previous refills. No customer payments were made, refunded or transferred in this task.

## Refund policy

The user delegated the decision after proposing that the first tiny use make a $5 block nonrefundable. The adopted policy refunds unused paid credit based on actual settled usage and prior refunds, without forfeiting an entire $5 block. Complimentary credits have no cash refund value. Pending/uncertain requests require reconciliation rather than being labelled consumed. Statutory withdrawal rights, billing corrections and defective-service remedies remain applicable. Refunds remain handled through the existing operator/contact process and Stripe; no new automatic refund endpoint was added.

Sources checked:
- https://www.gesetze-im-internet.de/bgb/__357a.html
- https://europa.eu/youreurope/business/selling-in-eu/selling-goods-services/ecommerce-distance-selling/index_en.htm
- https://openrouter.ai/terms
- https://openrouter.zendesk.com/hc/en-us/articles/51680638594331-How-does-Auto-Top-Up-work-and-how-do-I-turn-it-on-or-off
- https://www.assemblyai.com/docs/faq/how-to-get-your-api-key

The public policy pages retain their existing temporary-draft label because the business address remains unconfirmed.

## Release and verification

The Worker was patched from the currently published artifact, preserving all other code, assets, secrets, account restrictions and provider settings. Version `096a9868-d3fa-4593-b2ae-436502f99af3`; readback SHA-256 `44c483c2f9b2d768bfbd42008464aad8ad4ab2a7aedef6b8c5bd61caeb00d036`. The public endpoints returned 200 and the operator report confirmed 70/30, $5 batches and no automatic transfers.

Artifacts and exact diff are under `build/margin-20`. Run `node margin-deployment-check.mjs` from billing-local to verify the retained artifact against mocked services. The fixture covers legacy partial/full refunds, new purchase conversion, allocation, account isolation, persisted key limits and payment replay.

105 billing tests, Cloudflare integration, the scoped Worker fixture and 348 Swift tests passed. Canonical app S2T 1.0.1 Build 640 includes the updated offline policies and passed `--verify-build`. Website checks inspect the DOM and assets without screenshots. The full current-source browser suite also checks fractional amounts and usage presentation. The older deployed dashboard lacks some unrelated fractional styling covered by that suite; retain its published behavior rather than publishing unrelated pending UI changes.

Published sites: credits deployment `dpl_5doi6DFrGzACwGe5skkoQM445Wsy`; main-site deployment `dpl_GM13w3nPpYhhAEiZhmXRt8JfZYWc`. Both domains passed post-publication checks for the new price, refund clause, preserved statutory-rights text and retained preview assets. The exact staged files are `/private/tmp/s2t-margin-20-40bOtx`. The complete current-source browser regression suite passed after updating expected metered amounts for the new conversion. The canonical Build 640 terms and refund HTML match source byte-for-byte.
