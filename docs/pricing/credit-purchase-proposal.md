# Credit purchasing proposal

Approved and implemented September 19, 2026. The volume tiers below are now published on the private allowlisted credits service. Each credit remains $0.005 of provider usage. The economic scenarios are estimates, not an actual tax registration or a verified profit guarantee. See docs/verification/volume-pricing.md. The earlier loss warning concerned allocating 80% of gross customer payments to providers.

## Recommended packs

Keep the current value of one credit and grant more credits on larger purchases. Prices below are USD totals paid by customers. The modeled VAT is included in those totals.

| Customer pays | Credits | Provider usage funded | More usage per dollar than today | Estimated contribution |
| ---: | ---: | ---: | ---: | ---: |
| $5 | 500 | $2.50 | 0% | $0.98 |
| $10 | 1,100 | $5.50 | 10% | $1.73 |
| $20 | 2,300 | $11.50 | 15% | $3.24 |
| $50 | 5,800 | $29.00 | 16% | $8.30 |
| $100 | 11,800 | $59.00 | 18% | $15.85 |

Contribution assumes all credits are consumed. It is after modeled VAT, provider usage, funding fees, payment and conversion fees, a tax-service provision and a 2% operating-risk provision. It is before fixed overhead and income, corporation or trade tax. It is not an immediately available payout allowance. Unused prepaid service obligations and refundable amounts still need cash coverage.

The German VAT base case retains about 19–23% of revenue excluding VAT after those costs and provisions. Larger purchases improve customer value. They cannot eliminate percentage fees, VAT or the cost of providing and supporting S2T.

## Explicit assumptions

- A German standard-VAT scenario at 19%, with full eligibility to deduct provider input VAT. This is a planning scenario, not a finding that S2T is registered or that all customers use the German rate.
- Stripe standard EEA cards at 1.5% plus EUR 0.25. For USD checkout the model budgets a further 2% payment conversion cost and converts the fixed fee to $0.30 using an illustrative 1.20 USD/EUR. Neither the exchange rate nor settlement configuration is represented as verified account data.
- Another 0.5% of purchase price is reserved for tax calculation service. Stripe Tax Basic quotes that rate for its Checkout integration where applicable. It is not currently enabled by this proposal.
- A 70/30 OpenRouter/AssemblyAI usage mix, OpenRouter Standard's 5.5% funding fee and no separately assumed AssemblyAI funding surcharge. Provider usage itself is fully included. Actual invoices and usage mix can differ.
- Provider funding occurs in OpenRouter purchases of at least $25, so its $0.80 minimum does not dominate. A separate 1% FX allowance applies to provider purchases. The existing $5 internal accounting batch is not a card purchase instruction.
- A 2% provision is retained for refunds, disputes, failed sessions and operating variability. This is an assumption, not a guarantee that losses stay under 2%. Hosting, support and other fixed overhead still come from the contribution shown.

Stripe's public German pricing and OpenRouter's current pricing were checked. No authenticated Stripe settlement schedule, negotiated provider contract or actual tax registration was verified. Sources: [Stripe Germany pricing](https://stripe.com/de/pricing), [OpenRouter pricing](https://openrouter.ai/pricing), [OpenRouter funding minimum](https://openrouter.ai/blog/insights/openrouter-vs-litellm/).

## Tax treatment

Provider expenses generally reduce business profit for income-tax purposes. Sending money straight to a provider does not create an additional exemption. The timing of expense recognition and prepaid credits depends on the applicable accounting method. See [EStG §4](https://www.gesetze-im-internet.de/estg/__4.html).

VAT concerns the sale, not just S2T's retained markup. A VAT-inclusive EUR 100 domestic sale contains EUR 15.97 VAT, leaving EUR 84.03 net revenue. Spending EUR 80 on provider costs then leaves only EUR 4.03 before payment/funding fees. Eligible input VAT is deductible under [UStG §15](https://www.gesetze-im-internet.de/ustg_1980/__15.html). Imported B2B services can require reverse charge under [UStG §13b](https://www.gesetze-im-internet.de/ustg_1980/__13b.html), usually with a matching deduction where the business qualifies. Do not add irrecoverable provider VAT to a normal-VAT model when a valid deduction applies, and do not assume every supplier tax or invoice is deductible.

The current architecture sells S2T services and purchases provider services for S2T. It does not establish an agency relationship just by earmarking 70/30 or splitting a payment. Amounts treated as true pass-through items must be collected and spent in another party's name and for their account. See [UStG §10](https://www.gesetze-im-internet.de/ustg_1980/__10.html).

Kleinunternehmer treatment can exempt qualifying sales, but generally removes input-VAT deduction. Foreign service purchases can still create reverse-charge VAT payable by the small business. The model therefore includes 19% nonrecoverable VAT on the provider bill and the tax-service provision, without subtracting output VAT. Illustrative contributions become $1.28, $2.24, $4.15, $10.51 and $20.08. Actual eligibility and invoices need review. The ordinary thresholds are EUR 25,000 in the preceding year and EUR 100,000 in the current year; in a new business's first year the relevant ceiling is EUR 25,000. Other activity of the same entrepreneur can affect eligibility. Sources: [UStG §19](https://www.gesetze-im-internet.de/ustg_1980/__19.html), [BMF 2026 VAT instructions](https://www.bundesfinanzministerium.de/Content/DE/Downloads/BMF_Schreiben/Steuerarten/Umsatzsteuer/2025-12-29-muster-USt-erklaerung-2026.pdf?__blob=publicationFile&v=2).

EU consumer digital-service sales can use the customer's VAT rate. The EUR 10,000 cross-border threshold has conditions and is separate from the small-business thresholds. Do not apply a blanket 19% worldwide. An OSS or applicable small-business arrangement needs review for the actual sales footprint. See [European Commission OSS guidance](https://vat-one-stop-shop.ec.europa.eu/one-stop-shop_en).

## Stress case and limits

The calculator also combines 27% output VAT, a 3.15% international-card fee, 2% Stripe conversion, $0.30 fixed fee, 0.5% tax-service provision, 100% OpenRouter usage at its 8% Business rate, 2% provider FX and a 2% risk provision. Contributions remain positive at $0.50, $0.75, $1.25, $3.30 and $5.80, but are much thinner and still exclude fixed overhead and profit taxes. This is sensitivity analysis, not a universal maximum cost.

The 70/30 budget must not be presented as a guaranteed real usage mix. Provider refills need to follow measured balances and consumption. Refinancing old provider balances or paying out unconsumed purchase money is not profit. No auto-refill or payout setting was changed.

S2T's product value is dictation, cleanup, dictionary integration and managing multiple providers without separate customer API accounts. A resale layer paying retail provider prices cannot sustainably guarantee more raw AI usage per dollar than buying direct while also retaining a margin. Keep personal API keys available for customers who prefer direct billing. Separately charging for app access could fund development without an AI markup, but that would be a different product decision.

## Implementation requirements before publication

Keep one credit worth $0.005 of metered provider usage. Snapshot the granted provider amount and price version on each new checkout. Preserve all existing balances, holds and outstanding checkout quotes. Show the exact purchase grant in the dashboard and Stripe description, including purchase history, rather than assuming credits always equal paid cents. Refund paid unused value using that purchase's original grant, including any volume bonus, with statutory rights preserved. Keep custom amounts continuous and monotonic if they remain available; do not apply discontinuous percentage jumps that allow a one-cent purchase increase to create a large grant.

The present Stripe webhook intentionally rejects sessions carrying tax, shipping or discounts. Enabling Stripe Tax alone would therefore prevent those sessions from granting credit. Any tax launch must first update and verify the quoted tax-inclusive total, net revenue and credit grant across Checkout, webhook verification and refunds. Do not enable tax collection by inventing registration details or assume the existing tax-zero path is ready for a VAT-registered public launch.

Pricing and tax treatment should be agreed before changing customer-facing purchase terms. A German Steuerberater should confirm registration choice, input-VAT treatment, credit tax timing and cross-border obligations from the actual business setup. The calculator makes no such election.

Reproduce the figures with `python3 docs/pricing/credit-economics.py`. Full-precision CSV and inputs are in `build/pricing-economics`. The calculator reconciles the $100 allocation and checks positive contribution in each modeled case. It is deliberately separate from production billing.
