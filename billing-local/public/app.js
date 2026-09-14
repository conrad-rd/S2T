const $ = (id) => document.getElementById(id);
let account;
const money = (cents) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100);
const number = (value) =>
  new Intl.NumberFormat("en-US", { maximumFractionDigits: 4 }).format(value);
function amount() {
  return Math.round(Number($("amount").value) * 100);
}
function status(message) {
  $("status").textContent = message;
}
async function api(path, body, headers = {}) {
  const res = await fetch(
    path,
    body === undefined
      ? {}
      : {
          method: "POST",
          headers: { "Content-Type": "application/json", ...headers },
          body: JSON.stringify(body),
        },
  );
  const data = await res.json();
  if (!res.ok) throw Error(data.error);
  return data;
}
function updateAmount() {
  const cents = amount(),
    valid = $("amount").validity.valid && cents >= 100 && cents <= 10000;
  $("preview-credits").textContent = valid ? number(cents) : "—";
  $("purchase").disabled = !valid || (account && account.mode !== "demo");
  $("purchase").textContent = valid ? `Try a ${money(cents)} demo top-up ↗` : "Choose $1 to $100";
  document
    .querySelectorAll("[data-amount]")
    .forEach((b) => b.setAttribute("aria-pressed", Number(b.dataset.amount) * 100 === cents));
}
function empty(container, text) {
  const p = document.createElement("p");
  p.className = "muted";
  p.textContent = text;
  container.append(p);
}
async function refresh() {
  account = await api("/api/account");
  $("balance").textContent = number(account.available);
  $("held-balance").textContent =
    account.reserved > 0
      ? `${number(account.reserved)} credits reserved for pending requests.`
      : "No credits reserved.";
  $("stripe-link").href = account.paymentLink;
  const active = account.keys.filter((k) => !k.revoked && k.expires > Date.now());
  $("create-key").disabled = account.balance <= 0 || active.length >= 10 || account.frozen;
  $("key-count").textContent = active.length
    ? `${active.length} active demo key${active.length === 1 ? "" : "s"}.`
    : "";
  const keys = $("key-list");
  keys.replaceChildren();
  for (const key of active) {
    const row = document.createElement("div");
    row.className = "key-row";
    const label = document.createElement("span");
    label.textContent = `•••• ${key.suffix}`;
    const revoke = document.createElement("button");
    revoke.className = "secondary";
    revoke.textContent = "Revoke";
    revoke.setAttribute("aria-label", `Revoke key ending ${key.suffix}`);
    revoke.addEventListener("click", async () => {
      revoke.disabled = true;
      try {
        await api("/api/keys/revoke", { id: key.id });
        if ($("key-value").value.endsWith(key.suffix)) {
          $("key-value").value = "";
          $("key-result").hidden = true;
        }
        await refresh();
        status("Key revoked. It can no longer start requests.");
      } catch (e) {
        status(e.message);
        revoke.disabled = false;
      }
    });
    row.append(label, revoke);
    keys.append(row);
  }
  $("service-state").textContent = account.paused
    ? "Spending paused"
    : account.frozen
      ? "Account frozen"
      : "Limits active";
  $("try-request").disabled =
    account.mode !== "demo" || account.paused || account.frozen || account.available <= 0;
  const history = $("history");
  history.replaceChildren();
  if (!account.purchases.length) empty(history, "Your first top-up will appear here.");
  for (const p of account.purchases) {
    const row = document.createElement("div");
    row.className = "transaction";
    const label = document.createElement("span");
    label.textContent = `${money(p.cents)} · ${p.id.startsWith("demo_") ? "Demo top-up" : "Stripe payment"}`;
    const date = document.createElement("small");
    date.textContent =
      new Date(p.created).toLocaleString() + (p.reversed ? ` · ${money(p.reversed)} reversed` : "");
    label.append(date);
    const value = document.createElement("strong");
    value.textContent = `+${number(p.cents - p.reversed)} credits`;
    row.append(label, value);
    history.append(row);
  }
  const requests = $("requests");
  requests.replaceChildren();
  if (!account.requests.length)
    empty(requests, "No requests yet. Try a metered demo request above.");
  for (const r of account.requests) {
    const row = document.createElement("div");
    row.className = "transaction";
    const label = document.createElement("span");
    label.textContent = `${r.provider} · ${r.state}`;
    const date = document.createElement("small");
    date.textContent = new Date(r.created).toLocaleString();
    label.append(date);
    const cost = document.createElement("strong");
    cost.textContent =
      r.state === "settled"
        ? `${number(r.charged / 9000)} credits`
        : r.state === "released"
          ? "Released"
          : `${number(r.reserved / 9000)} reserved`;
    row.append(label, cost);
    requests.append(row);
  }
  updateAmount();
}
$("amount").addEventListener("input", updateAmount);
document.querySelectorAll("[data-amount]").forEach((b) =>
  b.addEventListener("click", () => {
    $("amount").value = b.dataset.amount;
    updateAmount();
  }),
);
$("purchase").addEventListener("click", async () => {
  $("purchase").disabled = true;
  try {
    await api("/api/demo/purchase", { cents: amount() });
    await refresh();
    status("Demo credits added. No payment was taken.");
  } catch (e) {
    status(e.message);
  } finally {
    updateAmount();
  }
});
$("create-key").addEventListener("click", async () => {
  $("create-key").disabled = true;
  try {
    const data = await api("/api/keys", {});
    $("key-result").hidden = false;
    $("key-value").value = data.key;
    await refresh();
    status(
      "Demo key created. Copy it now. It can access only synthetic requests on this local server.",
    );
  } catch (e) {
    status(e.message);
    $("create-key").disabled = false;
  }
});
$("copy-key").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText($("key-value").value);
    status("Demo key copied.");
  } catch {
    $("key-value").select();
    status("Select and copy the key from the field.");
  }
});
$("try-request").addEventListener("click", async () => {
  $("try-request").disabled = true;
  $("request-result").textContent = "Reserving credits and running the synthetic request…";
  try {
    const result = await api("/api/demo/request", {}, { "Idempotency-Key": crypto.randomUUID() });
    $("request-result").textContent =
      result.state === "settled"
        ? `Completed. Charged ${number(result.chargedCredits)} credit; the unused reservation was released.`
        : "Outcome uncertain. Credits remain reserved and new spending is paused.";
    await refresh();
  } catch (e) {
    $("request-result").textContent = e.message;
    await refresh();
  }
});
refresh().catch((e) => status(e.message));
updateAmount();
window.addEventListener("focus", () => refresh().catch((e) => status(e.message)));
