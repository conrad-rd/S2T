const $ = (id) => document.getElementById(id);
let account;
let clerk;
let purchaseAttempt;
let refreshGeneration = 0;
const connectionCode = new URLSearchParams(location.search).get("connect");
if (connectionCode && /^[A-F0-9]{12}$/.test(connectionCode)) sessionStorage.setItem("s2t-connect-code", connectionCode);
const pendingConnection = sessionStorage.getItem("s2t-connect-code");
if (pendingConnection) {
  $("connect-panel").hidden = false;
  $("connect-code").textContent = pendingConnection.match(/.{1,4}/g).join("-");
}
$("connect-approve").addEventListener("click", async () => {
  $("connect-approve").disabled = true;
  try {
    await api("/api/device/approve", { userCode: pendingConnection });
    sessionStorage.removeItem("s2t-connect-code");
    $("connect-status").textContent = "Connected. Return to S2T. You can add credits here whenever needed.";
    await refresh();
  } catch (error) {
    $("connect-status").textContent = error.message;
    $("connect-approve").disabled = false;
  }
});
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
  const token = clerk?.session ? await clerk.session.getToken({ template: "s2t" }) : null;
  const res = await fetch(path, {
    method: body === undefined ? "GET" : "POST",
    headers: { ...(body === undefined ? {} : { "Content-Type": "application/json" }), ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const data = await res.json();
  if (!res.ok) throw Error(data.error);
  return data;
}
function updateAmount() {
  const cents = amount(),
    valid = $("amount").validity.valid && cents >= 100 && cents <= 10000;
  $("preview-credits").textContent = valid ? number(cents) : "—";
  $("purchase").disabled = !valid || !account || (account.mode !== "demo" && !account.checkoutEnabled) || account.frozen;
  $("purchase").textContent = valid ? account?.mode === "demo" ? `Try a ${money(cents)} demo top-up ↗` : `Buy ${number(cents)} credits for ${money(cents)} ↗` : "Choose $1 to $100";
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
  const generation = ++refreshGeneration;
  const updated = await api("/api/account");
  if (generation !== refreshGeneration) return;
  account = updated;
  $("balance").textContent = number(account.available);
  $("held-balance").textContent =
    account.reserved > 0
      ? `${number(account.reserved)} credits reserved for pending requests.`
      : "No credits reserved.";
  const demo = account.mode === "demo";
  $("account-content").hidden = false;
  $("mode-badge").textContent = demo ? "Local preview" : account.mode === "test" ? "Stripe sandbox" : "S2T credits";
  $("wallet-mode").textContent = demo ? "Demo wallet" : account.mode === "test" ? "Test wallet" : "Prepaid wallet";
  $("purchase-note").textContent = demo ? "Demo only. No payment is taken and these credits cannot buy API usage." : account.mode === "test" ? account.realProviders ? "Stripe sandbox for approved testers. Payments are simulated; dictation uses real providers." : "Stripe sandbox. Use test payment details. Provider requests remain synthetic." : "One-time purchase through Stripe. Credits appear after payment is confirmed. No automatic refill.";
  $("create-key").textContent = demo ? "Create demo key" : "Create S2T key";
  $("demo-panel").hidden = !demo;
  $("footer-mode").textContent = demo ? "Local preview · No real payments" : account.mode === "test" ? account.realProviders ? "Private sandbox · Real dictation" : "Sandbox · No real provider usage" : "Prepaid transcription and cleanup";
  const active = account.keys.filter((k) => !k.revoked && k.expires > Date.now());
  $("create-key").disabled = active.length >= 10 || account.frozen;
  $("key-count").textContent = active.length
    ? `${active.length} active key${active.length === 1 ? "" : "s"}.`
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
    empty(requests, demo ? "No requests yet. Try a metered demo request above." : "Your dictation and cleanup usage will appear here.");
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
    if (account.mode === "demo") {
      await api("/api/demo/purchase", { cents: amount() });
      await refresh();
      status("Demo credits added. No payment was taken.");
    } else {
      if (!purchaseAttempt || purchaseAttempt.cents !== amount()) purchaseAttempt = { cents: amount(), id: crypto.randomUUID() };
      const checkout = await api("/api/checkout", { cents: purchaseAttempt.cents }, { "Idempotency-Key": purchaseAttempt.id });
      const url = new URL(checkout.url);
      if (url.origin !== "https://checkout.stripe.com") throw Error("Checkout returned an unexpected address.");
      location.assign(url.href);
    }
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
      account.mode === "live" || account.realProviders ? "S2T key created. Copy it now and save it in the Mac app." : "Test key created. Copy it now. Requests use synthetic providers.",
    );
  } catch (e) {
    status(e.message);
    $("create-key").disabled = false;
  }
});
$("copy-key").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText($("key-value").value);
    status("S2T key copied.");
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
async function start() {
  const config = await (await fetch("/api/config")).json();
  $("mode-badge").textContent = config.mode === "demo" ? "Local preview" : config.mode === "test" ? "Stripe sandbox" : "S2T credits";
  $("footer-mode").textContent = config.mode === "demo" ? "Local preview · No real payments" : config.mode === "test" ? "Sandbox · No real payments" : "Prepaid transcription and cleanup";
  if (config.clerk) {
    const load = (path, attributes = {}) => new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = config.clerk.origin + path;
      script.crossOrigin = "anonymous";
      for (const [name, value] of Object.entries(attributes)) script.setAttribute(name, value);
      script.onload = resolve;
      script.onerror = () => reject(Error("Sign-in could not load. Please reload the page."));
      document.head.append(script);
    });
    await load("/npm/@clerk/ui@1/dist/ui.browser.js");
    await load("/npm/@clerk/clerk-js@6/dist/clerk.browser.js", { "data-clerk-publishable-key": config.clerk.publishableKey });
    clerk = window.Clerk;
    await clerk.load({ ui: { ClerkUI: window.__internal_ClerkUICtor } });
    let lastUser;
    clerk.addListener(({ user }) => {
      if (lastUser === user?.id) return;
      lastUser = user?.id;
      refreshGeneration++;
      account = null;
      purchaseAttempt = null;
      $("key-value").value = "";
      $("key-result").hidden = true;
      $("account-content").hidden = !user;
      $("sign-in").hidden = !!user;
      if (user) { clerk.unmountSignIn($("sign-in")); clerk.mountUserButton($("user-button")); refresh().catch(e => status(e.message)); }
      else { clerk.mountSignIn($("sign-in")); }
    });
    if (!clerk.user) { $("sign-in").hidden = false; clerk.mountSignIn($("sign-in")); }
  } else if (config.mode !== "live") await refresh();
  else throw Error("Customer sign-in has not been configured.");
  const returned = new URLSearchParams(location.search).get("checkout");
  if (returned === "returned") status("Checking your balance. A checkout return alone does not confirm payment; credits appear after Stripe confirms it.");
  if (returned === "cancelled") status("Checkout cancelled. No credits were added by this page.");
}
start().catch(e => status(e.message));
updateAmount();
window.addEventListener("focus", () => { if (account) refresh().catch(e => status(e.message)); });
setInterval(() => { if (account && !document.hidden) refresh().catch(e => status(e.message)); }, 10000);
