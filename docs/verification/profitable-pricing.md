# Profitable pricing

September 19, 2026. New purchases have a $5 minimum and $100 maximum. A dollar buys 100 credits; each credit covers $0.005 of provider usage. The remaining 50% of gross receipts covers taxes, payment and funding fees, and S2T. It is not net profit.

Existing balances and holds remain denominated in provider microdollars. Displayed credit counts change without reducing spending value. New checkout orders snapshot funding_rate=5000. Migration assigns 9000 to quotes created before the first pricing deployment at 2026-09-19T13:22:28.870Z and 8000 to later existing quotes. Historical sub-$5 quotes can settle. Grants require the quoted account and amount, and refunds use the original purchase grant divided by paid cents. Migration and grants are idempotent. Unused paid credit remains refundable under the published terms and statutory rights; no $5 forfeiture applies.

The funding report now names its retained amount retainedBeforeTaxAndFeesMicros. The 70/30 provider split and usage-earned $5 batches are internal accounting. Transfers remain manual and availableForPayout remains null. No tax registration, automatic tax collection or provider refill automation was enabled.

Planning estimates use German VAT registration, 19% VAT included in the price, Stripe standard EEA 1.5% plus EUR 0.25, an assumed 2% currency conversion fee, EUR/USD 1.146, and a 5.5% OpenRouter funding fee on 70% of provider usage. Recoverable input VAT is excluded. Estimated contribution is $1.14 on $5, $2.57 on $10, $5.44 on $20, $14.02 on $50 and $28.32 on $100. These amounts precede overhead, refunds, disputes and income tax. Actual account fees and tax treatment were not verified. The independent stress case remains positive with 27% VAT, 5.5% payment fees plus $0.35, and a 16% funding fee on all AI cost.

Sources: https://stripe.com/de/pricing, https://openrouter.ai/business, https://www.gesetze-im-internet.de/ustg_1980/__12.html and https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html.

## Release and verification

- Worker 1e6ddc0b-e2a7-45c1-b998-98c47df1e81a. Exact readback SHA-256 110b907605ecb3f57a7de9c2a52393073f93396772e6f7d79ced984f60119028. Scoped artifact and deployment evidence are in build/profitable-pricing. Existing live bindings, secrets and unrelated source were retained.
- Credits dpl_7o96ggbvyWBVNvDMKGqg3bfjwNdi and home dpl_Fz2ms3EYf26zPq89Gb7suWQMkQok were staged from published assets, changing only the pricing and applicable terms.
- Billing npm test, Cloudflare integration, local browser checks, the exact Worker fixture profitable-deployment-check.mjs and profitable-browser-check.mjs passed. Live dashboard checks use isolated billing responses and verify minimums, presets, conversion, metering and responsive layout. Both published sites passed pricing, policy and asset DOM checks.
- 380 Swift tests passed. Canonical build/S2T.app is S2T 1.0.1 Build 650. --verify-build confirms executable, bundle and menu identity. Bundled terms and refunds match the source pages byte for byte.

No real payments, provider inference, customer data mutations or screenshots were used for verification. Actual Stripe settlement and tax remittance were not exercised.
