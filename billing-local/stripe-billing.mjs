import Stripe from "stripe";
import { requireThat, integer } from "./money.mjs";
export function createStripeBilling({
  ledger,
  mode,
  secret,
  paymentLinkId,
  apiKey,
  stripeClient,
  paymentLinkURL,
}) {
  const stripe =
    stripeClient || (apiKey ? new Stripe(apiKey, { maxNetworkRetries: 0, timeout: 10000 }) : null);
  async function webhook(raw, signature) {
    requireThat(
      secret && stripe && paymentLinkId,
      "stripe_disabled",
      "Stripe fulfillment is not configured.",
      503,
    );
    let event;
    try {
      event = Stripe.webhooks.constructEvent(raw, signature, secret, 300);
    } catch {
      requireThat(false, "signature", "Invalid Stripe signature.", 400);
    }
    requireThat(
      event.livemode === (mode === "live") && !event.account,
      "stripe_mode",
      "Unexpected Stripe account or payment mode.",
    );
    if (
      ["checkout.session.completed", "checkout.session.async_payment_succeeded"].includes(
        event.type,
      )
    ) {
      const id = event.data?.object?.id;
      requireThat(
        typeof id === "string" && id.startsWith("cs_"),
        "checkout",
        "Invalid checkout identifier.",
      );
      const session = await stripe.checkout.sessions.retrieve(id, { expand: ["payment_intent"] });
      requireThat(
        session.id === id &&
          session.livemode === (mode === "live") &&
          session.payment_link === paymentLinkId &&
          session.mode === "payment" &&
          session.currency === "usd",
        "checkout",
        "Checkout does not match this service.",
      );
      if (session.payment_status !== "paid") return { received: true };
      const pi = session.payment_intent;
      requireThat(
        pi &&
          typeof pi === "object" &&
          pi.status === "succeeded" &&
          pi.currency === "usd" &&
          pi.livemode === (mode === "live") &&
          pi.amount_received === session.amount_total,
        "payment",
        "Payment has not been confirmed.",
      );
      requireThat(
        !session.total_details?.amount_shipping &&
          !session.total_details?.amount_tax &&
          !session.total_details?.amount_discount,
        "pricing",
        "Tax, shipping, and discounts require an approved credit-pricing policy.",
      );
      integer(session.amount_total, 100, 10000, "Purchase");
      requireThat(
        typeof session.client_reference_id === "string",
        "account",
        "Checkout has no S2T account reference.",
      );
      ledger.grant({
        account: session.client_reference_id,
        cents: session.amount_total,
        session: id,
        intent: pi.id,
      });
    } else if (["refund.created", "refund.updated", "refund.failed"].includes(event.type)) {
      const r = await stripe.refunds.retrieve(event.data.object.id);
      requireThat(r.currency === "usd", "refund", "Unexpected refund currency.");
      if (r.status === "succeeded") {
        requireThat(
          typeof r.payment_intent === "string",
          "refund",
          "Refund payment reference is missing.",
        );
        ledger.reverse({ id: r.id, intent: r.payment_intent, cents: r.amount, kind: "refund" });
      }
    } else if (["charge.dispute.created", "charge.dispute.funds_withdrawn"].includes(event.type)) {
      const d = await stripe.disputes.retrieve(event.data.object.id);
      requireThat(
        d.currency === "usd" && typeof d.payment_intent === "string",
        "dispute",
        "Dispute payment reference is missing.",
      );
      ledger.reverse({ id: d.id, intent: d.payment_intent, cents: d.amount, kind: "dispute" });
    }
    return { received: true };
  }
  async function checkout(account) {
    requireThat(
      mode === "live" && stripe && paymentLinkId,
      "checkout_disabled",
      "Live checkout is not enabled.",
      503,
    );
    const link = await stripe.paymentLinks.retrieve(paymentLinkId);
    requireThat(
      link.active &&
        link.livemode === true &&
        link.url === paymentLinkURL &&
        !link.automatic_tax?.enabled &&
        !link.allow_promotion_codes &&
        !link.shipping_address_collection,
      "checkout_config",
      "Payment Link settings need review before accepting payments.",
      503,
    );
    const items = await stripe.paymentLinks.listLineItems(paymentLinkId, { limit: 2 });
    requireThat(
      items.data.length === 1 && !items.has_more,
      "checkout_config",
      "Only one credit product is supported.",
      503,
    );
    const item = items.data[0],
      price = item.price;
    requireThat(
      price?.currency === "usd" && price.type === "one_time" && item.quantity === 1,
      "checkout_config",
      "Checkout must sell one USD credit top-up.",
      503,
    );
    if (price.custom_unit_amount) {
      integer(price.custom_unit_amount.minimum, 100, 10000, "Minimum top-up");
      integer(
        price.custom_unit_amount.maximum,
        price.custom_unit_amount.minimum,
        10000,
        "Maximum top-up",
      );
    } else integer(price.unit_amount, 100, 10000, "Top-up");
    const url = new URL(link.url);
    url.searchParams.set("client_reference_id", account);
    return { url: url.href };
  }
  return { webhook, checkout };
}
