import { chromium } from "playwright";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { once } from "node:events";
import { createApplication } from "./server.mjs";
import { configuration } from "./config.mjs";
const config = configuration({ S2T_BILLING_DATA_DIR: mkdtempSync(tmpdir() + "/s2t-browser-") });
const app = createApplication(config);
app.server.listen(0, "127.0.0.1");
await once(app.server, "listening");
config.port = app.server.address().port;
config.origin = `http://localhost:${config.port}`;
const browser = await chromium.launch({ channel: "chrome", headless: true });
try {
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto(config.origin);
  await page.waitForFunction(() =>
    !document.querySelector("#account-content").hidden,
  );
  await page.locator("#purchase").click();
  await page.waitForFunction(() => document.querySelector("#balance").textContent === "500");
  await page.getByRole("button", { name: "Create demo key" }).click();
  await page.locator("#key-value").waitFor({ state: "visible" });
  assert.match(await page.locator("#key-value").inputValue(), /^s2t_demo_/);
  await page.reload();
  await page.waitForFunction(() => document.querySelector("#balance").textContent === "500");
  assert.equal(await page.locator("#key-result").isVisible(), false);
  await page.getByRole("button", { name: "Try a metered demo request" }).click();
  await page.waitForFunction(() => document.querySelector("#balance").textContent === "499.99");
  assert.match(await page.locator("#request-result").textContent(), /0.01/);
  await page.getByRole("button", { name: /Revoke key ending/ }).click();
  await page.waitForFunction(() => document.querySelectorAll(".key-row").length === 0);
  const pairing = await (await fetch(config.origin + "/api/device/start", { method: "POST" })).json();
  await page.goto(config.origin + "/?connect=" + pairing.userCode);
  await page.waitForFunction(() => !document.querySelector("#account-content").hidden);
  await page.getByRole("button", { name: "Connect this Mac", exact: true }).click();
  await page.waitForFunction(() => document.querySelector("#connect-status").textContent.startsWith("Connected."));
  const linked = await (await fetch(config.origin + "/api/device/poll", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ deviceCode: pairing.deviceCode }) })).json();
  assert.equal(linked.state, "approved");
  assert.match(linked.key, /^s2t_demo_/);
  await page.locator("#amount").fill("101");
  assert.equal(await page.locator("#purchase").isDisabled(), true);
  await page.setViewportSize({ width: 375, height: 812 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  assert.deepEqual(errors, []);
  console.log(
    "PASS: demo purchase, key issuance, persistence, metered request, exact fractional debit, revocation, browser-approved app connection, amount limit, mobile overflow, no browser errors. No screenshots or clipboard access.",
  );
} finally {
  await browser.close();
  await app.close();
}
