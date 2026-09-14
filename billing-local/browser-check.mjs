import { chromium } from "playwright";
import assert from "node:assert/strict";
const browser = await chromium.launch({ channel: "chrome", headless: true });
try {
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("http://localhost:4317");
  await page.waitForFunction(() =>
    document.querySelector("#stripe-link").href.startsWith("https://buy.stripe.com/"),
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
  await page.locator("#amount").fill("101");
  assert.equal(await page.locator("#purchase").isDisabled(), true);
  await page.setViewportSize({ width: 375, height: 812 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  assert.deepEqual(errors, []);
  console.log(
    "PASS: demo purchase, key issuance, persistence, metered request, exact fractional debit, revocation, amount limit, mobile overflow, no browser errors. No screenshots or clipboard access.",
  );
} finally {
  await browser.close();
}
