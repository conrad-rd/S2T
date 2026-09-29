"""Planning model only. Does not change checkout, tax settings or existing credit value."""
from decimal import Decimal as D
from pathlib import Path
import csv
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/pricing-economics"
OUT.mkdir(parents=True, exist_ok=True)
PACKS = [(5, 500), (10, 1100), (20, 2300), (50, 5800), (100, 11800)]
SCENARIOS = {
    "DE VAT, standard EEA card": dict(vat="0.19", card="0.015", payment_fx="0.02", tax_service="0.005", provider_fx="0.01", or_share="0.70", or_fee="0.055", input_vat="0"),
    "Kleinunternehmer illustration": dict(vat="0", card="0.015", payment_fx="0.02", tax_service="0.005", provider_fx="0.01", or_share="0.70", or_fee="0.055", input_vat="0.19"),
    "Stress case": dict(vat="0.27", card="0.0315", payment_fx="0.02", tax_service="0.005", provider_fx="0.02", or_share="1", or_fee="0.08", input_vat="0"),
}
FIXED_CARD_FEE_USD = D("0.30")  # EUR 0.25 at an assumed, not current, 1.20 USD/EUR.
OPERATING_RESERVE_RATE = D("0.02")  # Planning provision, not a tax or quoted fee.
USD_PER_CREDIT = D("0.005")  # Existing metering value, not a proposed revaluation.

def estimate(price, credits, parameters):
    p = {key: D(value) for key, value in parameters.items()}
    price = D(price)
    usage = D(credits) * USD_PER_CREDIT
    revenue = price / (1 + p["vat"])
    funding_fee = usage * p["or_share"] * p["or_fee"]
    provider_fx = (usage + funding_fee) * p["provider_fx"]
    provider_input_vat = (usage + funding_fee) * p["input_vat"]
    card = price * (p["card"] + p["payment_fx"]) + FIXED_CARD_FEE_USD
    tax_service = price * p["tax_service"]
    tax_service_input_vat = tax_service * p["input_vat"]
    reserve = price * OPERATING_RESERVE_RATE
    contribution = revenue - usage - funding_fee - provider_fx - provider_input_vat - card - tax_service - tax_service_input_vat - reserve
    return dict(price_usd=price, credits=D(credits), usage_usd=usage, output_vat_usd=price-revenue,
        revenue_ex_vat_usd=revenue, provider_funding_fee_usd=funding_fee, provider_fx_usd=provider_fx,
        nonrecoverable_provider_vat_usd=provider_input_vat, stripe_payment_usd=card,
        tax_service_usd=tax_service, nonrecoverable_tax_service_vat_usd=tax_service_input_vat,
        operating_reserve_usd=reserve, contribution_usd=contribution,
        contribution_pct_of_net_revenue=100*contribution/revenue,
        more_credits_than_current_pct=100*(D(credits)/(price*100)-1))

rows = []
for name, parameters in SCENARIOS.items():
    for price, credits in PACKS:
        rows.append(dict(scenario=name, **estimate(price, credits, parameters)))

with (OUT / "proposed-tiers.csv").open("w", newline="") as file:
    writer = csv.DictWriter(file, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
(OUT / "assumptions.json").write_text(json.dumps(dict(status="proposal_not_deployed", scenarios=SCENARIOS,
    fixed_card_fee_usd=str(FIXED_CARD_FEE_USD), assumed_usd_per_eur="1.20", operating_reserve_rate=str(OPERATING_RESERVE_RATE),
    credit_provider_value_usd=str(USD_PER_CREDIT), openrouter_refill_minimum_usd="25",
    exclusions=["fixed overhead", "income/corporation/trade taxes", "losses exceeding provision", "unverified account-specific fees"]), indent=2)+"\n")

print("Price | Credits | Raw AI value | DE contribution | Net revenue margin | KU contribution | Stress contribution")
for price, credits in PACKS:
    values = [estimate(price, credits, p) for p in SCENARIOS.values()]
    main, small, stress = values
    assert all(v["contribution_usd"] > 0 for v in values)
    print(f'${price} | {credits:,} | ${main["usage_usd"]:.2f} | ${main["contribution_usd"]:.2f} | {main["contribution_pct_of_net_revenue"]:.1f}% | ${small["contribution_usd"]:.2f} | ${stress["contribution_usd"]:.2f}')

# Independent cash reconciliation of the largest German VAT example.
largest = estimate(100, 11800, SCENARIOS["DE VAT, standard EEA card"])
assert largest["usage_usd"] == D("59")
assert largest["provider_funding_fee_usd"] == D("2.2715")
assert largest["stripe_payment_usd"] == D("3.8")
assert largest["tax_service_usd"] == D("0.5")
assert largest["operating_reserve_usd"] == D("2")
assert largest["contribution_usd"].quantize(D("0.01")) == D("15.85")
assert sum(largest[k] for k in ["output_vat_usd", "usage_usd", "provider_funding_fee_usd", "provider_fx_usd",
    "nonrecoverable_provider_vat_usd", "stripe_payment_usd", "tax_service_usd", "nonrecoverable_tax_service_vat_usd",
    "operating_reserve_usd", "contribution_usd"]).quantize(D("0.01")) == D("100.00")
print("PASS: positive contribution in all modeled cases; $100 cash allocation reconciles.")
