import { chromium } from "playwright";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
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
const origin = process.env.S2T_DASHBOARD_ORIGIN || config.origin;
const browser = await chromium.launch({ channel: "chrome", headless: true });
try {
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  if (process.env.S2T_DASHBOARD_ORIGIN) await page.route('**/api/**', async route => {
    const request = route.request(), url = new URL(request.url());
    const response = await route.fetch({ url: config.origin + url.pathname + url.search, headers: { ...request.headers(), origin: config.origin } });
    await route.fulfill({ response });
  });
  if (process.env.S2T_DASHBOARD_ASSETS) await page.route('**/*', async route => {
    const path = new URL(route.request().url()).pathname;
    if (['/', '/index.html', '/app.js', '/style.css', '/fonts/bitcount-regular.ttf'].includes(path)) return route.fulfill({ body: readFileSync(resolve(process.env.S2T_DASHBOARD_ASSETS, path === '/' ? 'index.html' : path.slice(1))), contentType: path.endsWith('.js') ? 'application/javascript' : path.endsWith('.css') ? 'text/css' : path.endsWith('.ttf') ? 'font/ttf' : 'text/html' });
    return route.fallback();
  });
  await page.goto(origin);
  await page.waitForFunction(() =>
    !document.querySelector("#account-content").hidden,
  );
  assert.equal(await page.locator('#usage-total').textContent(), '0.0000');
  assert.equal(await page.locator('#last-used').textContent(), 'Not used yet');
  assert.equal(await page.locator('#usage-chart button').count(), 30);
  assert.equal(await page.locator('#open-purchase').textContent(), 'Add credits');
  assert.doesNotMatch(await page.locator('#purchase').textContent(), /[\u2190-\u21ff]/);
  for (const id of ['activity-details', 'topup-details', 'keys-details']) assert.equal(await page.locator('#' + id).getAttribute('open'), null);
  assert.equal(await page.locator('#purchase-dialog').isVisible(), false);
  await page.locator('#open-purchase').focus();
  await page.keyboard.press('Enter');
  await page.locator('#purchase-dialog').waitFor({ state: 'visible' });
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('#open-purchase').evaluate(el => el === document.activeElement), true);
  await page.locator('#open-purchase').click();
  for (const value of ['5', '10', '20', '50']) {
    await page.locator('#amount').fill(value);
    assert.doesNotMatch(await page.locator('#purchase').textContent(), /[\u2190-\u21ff]/);
  }
  await page.locator('#amount').fill('5');
  await page.locator("#purchase").click();
  await page.waitForFunction(() => document.querySelector("#balance").textContent === "500.0000");
  await page.locator('#keys-details > summary').click();
  await page.getByRole("button", { name: "Create demo key" }).click();
  await page.locator("#key-value").waitFor({ state: "visible" });
  assert.match(await page.locator("#key-value").inputValue(), /^s2t_demo_/);
  await page.reload();
  await page.waitForFunction(() => document.querySelector("#balance").textContent === "500.0000");
  assert.equal(await page.locator("#key-result").isVisible(), false);
  await page.getByRole("button", { name: "Try a metered demo request" }).click();
  await page.waitForFunction(() => document.querySelector("#balance").textContent === "499.9820");
  assert.match(await page.locator("#request-result").textContent(), /0.01/);
  assert.equal(await page.locator('#usage-total').textContent(), '0.0180');
  assert.equal(await page.locator('#last-device').textContent(), 'Not recorded');
  await page.locator('[data-days="7"]').click();
  await page.waitForFunction(() => document.querySelectorAll('#usage-chart button').length === 7);
  await page.locator('[data-days="90"]').click();
  await page.waitForFunction(() => document.querySelectorAll('#usage-chart button').length === 90);
  await page.locator('#usage-chart button').last().focus();
  await page.keyboard.press('Home');
  assert.equal(await page.locator('#usage-chart button').first().evaluate(el => el === document.activeElement), true);
  await page.locator('#keys-details > summary').click();
  await page.getByRole("button", { name: /Revoke key ending/ }).click();
  await page.waitForFunction(() => document.querySelectorAll(".key-row").length === 0);
  const pairing = await (await fetch(config.origin + "/api/device/start", { method: "POST" })).json();
  await page.goto(origin + "/?connect=" + pairing.userCode);
  await page.waitForFunction(() => !document.querySelector("#account-content").hidden);
  await page.getByRole("button", { name: "Connect this Mac", exact: true }).click();
  await page.waitForFunction(() => document.querySelector("#connect-status").textContent.startsWith("Connected."));
  const linked = await (await fetch(config.origin + "/api/device/poll", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ deviceCode: pairing.deviceCode }) })).json();
  assert.equal(linked.state, "approved");
  assert.match(linked.key, /^s2t_demo_/);
  const result = await fetch(config.origin + '/api/v1/requests', { method: 'POST', headers: { Authorization: 'Bearer ' + linked.key, 'Content-Type': 'application/json', 'Idempotency-Key': 'dashboard-device-fixture', 'X-S2T-Device-Id': 'a42fb61a-8053-4336-9482-b3e5f27ec7a1', 'X-S2T-Device-Name': 'MacBook Pro' }, body: JSON.stringify({ provider: 'openrouter', operation: 'cleanup', text: 'Dashboard fixture.' }) });
  assert.equal(result.status, 200);
  await page.reload();
  await page.waitForFunction(() => document.querySelector('#last-device').textContent === 'MacBook Pro');
  assert.match(await page.locator('#device-detail').textContent(), /C7A1/);
  assert.equal(await page.locator('#usage-total').textContent(), '0.0360');
  await page.locator('#open-purchase').click();
  await page.locator("#amount").fill("101");
  assert.equal(await page.locator("#purchase").isDisabled(), true);
  await page.setViewportSize({ width: 375, height: 812 });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.keyboard.press('Escape');
  for (const width of [320, 375, 768, 1280]) {
    await page.setViewportSize({ width, height: 900 });
    await page.evaluate(() => new Promise(requestAnimationFrame));
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Overflow at ${width}px`);
  }
  await page.evaluate(() => document.fonts.ready);
  assert.equal(await page.evaluate(() => document.fonts.check('40px Bitcount')), true);
  assert.match(await page.locator('#balance').evaluate(el => getComputedStyle(el).fontFamily), /Bitcount/);
  assert.equal(await page.locator('.usage-card').evaluate(el => getComputedStyle(el).backgroundImage), 'none');
  assert.equal(await page.locator('.brand img').evaluate(el => Math.abs(el.getBoundingClientRect().width / el.getBoundingClientRect().height - 70 / 29) < .01), true);
  await page.route('**/api/account?*', async route => {
    const url = new URL(route.request().url());
    const response = await route.fetch({ url: config.origin + url.pathname + url.search });
    const fixture = await response.json();
    fixture.usage.spentCredits = 7;
    fixture.usage.requestCount = 3;
    fixture.usage.series = fixture.usage.series.map((day, index, days) => ({ ...day, credits: [1, 2, 4][index - days.length + 3] ?? 0, requests: index >= days.length - 3 ? 1 : 0 }));
    await route.fulfill({ response, json: fixture });
  });
  await page.reload();
  await page.waitForFunction(() => document.querySelector('#usage-total').textContent === '7.0000');
  const columns = page.locator('.chart-day:not([data-empty=true])');
  assert.equal(await columns.count(), 3);
  const heights = await columns.locator('.chart-bar').evaluateAll(nodes => nodes.map(node => node.getBoundingClientRect().height));
  assert.ok(Math.abs(heights[0] * 2 - heights[1]) < 1 && Math.abs(heights[1] * 2 - heights[2]) < 1, 'Brand strokes must preserve the actual usage proportions');
  assert.equal(await columns.locator('svg path').count(), 3);
  assert.equal(await page.locator('.chart-day[data-empty=true] .chart-bar').first().isVisible(), false);
  await page.mouse.move(0, 0);
  assert.equal(await columns.last().locator('.chart-bar').evaluate(el => getComputedStyle(el).opacity), '0.5');
  await columns.last().click();
  assert.equal(await columns.last().locator('.chart-bar').evaluate(el => getComputedStyle(el).opacity), '1');
  assert.equal(await columns.last().evaluate(el => getComputedStyle(el).color), 'rgb(193, 193, 193)');
  assert.equal(await page.locator('#chart-connector').evaluate(el => getComputedStyle(el).backgroundColor), 'rgb(193, 193, 193)');
  assert.match(await page.locator('#chart-detail').textContent(), /4\.0000 credits/);
  assert.deepEqual(await page.locator('#chart-y-axis > span').allTextContents(), ['4.0000', '3.0000', '2.0000', '1.0000', '0.0000']);
  assert.equal(await page.locator('.usage-caption').count(), 0);
  assert.equal(await page.locator('#provider-usage').evaluate(el => getComputedStyle(el).borderTopWidth), '0px');
  assert.equal(await page.locator('#chart-connector').isVisible(), true);
  const detailBounds = await page.locator('#chart-detail').boundingBox();
  const plotBounds = await page.locator('.chart-wrap').boundingBox();
  assert.ok(detailBounds.x >= plotBounds.x && detailBounds.x + detailBounds.width <= plotBounds.x + plotBounds.width + 1);
  assert.ok(detailBounds.y >= plotBounds.y - 64 && detailBounds.y + detailBounds.height < plotBounds.y);
  const pillar = await columns.last().locator('.chart-bar').boundingBox();
  for (const fraction of [.25, .75]) {
    const x = pillar.x + pillar.width / 2, y = pillar.y + pillar.height * fraction;
    await page.mouse.move(x, y);
    const anchor = await page.locator('#chart-connector').evaluate(el => ({ x: parseFloat(el.style.left), y: parseFloat(el.style.top), transform: el.style.transform }));
    assert.ok(Math.abs(anchor.x + plotBounds.x - x) < 1 && Math.abs(anchor.y + plotBounds.y - y) < 1, 'Connector must start at the cursor');
    assert.match(anchor.transform, /rotate/);
  }
  await page.mouse.move(pillar.x - 2, pillar.y + pillar.height / 2);
  assert.equal(await page.locator('#chart-detail').isVisible(), false, 'Leaving the actual pillar must hide even when clicked/focused');
  assert.equal(await page.locator('#chart-connector').isVisible(), false);
  await page.locator('.period-control button').first().focus();
  await page.mouse.move(0, 0);
  await page.route('**/api/account?*', async route => {
    const url = new URL(route.request().url());
    const response = await route.fetch({ url: config.origin + url.pathname + url.search });
    const fixture = await response.json();
    fixture.available = 1 / 5000;
    fixture.reserved = 1 / 5000;
    fixture.keys = [{ id: 'decimal-fixture', suffix: 'abc123', expires: Date.now() + 86400000, limits: { limitCredits: 25.75, remainingCredits: 12.125, expiresAt: Date.now() + 86400000 } }];
    fixture.purchases = [{ id: 'demo_decimal', cents: 525, reversed: 125, created: Date.now() }];
    fixture.requests = [
      { provider: 'openrouter', state: 'settled', created: Date.now(), charged: 1 },
      { provider: 'openrouter', state: 'reserved', created: Date.now(), reserved: 1 },
    ];
    fixture.usage.spentCredits = 1 / 5000;
    fixture.usage.providers = [{ provider: 'openrouter', credits: 1 / 5000 }];
    fixture.usage.series = fixture.usage.series.map((day, index, days) => ({
      ...day, credits: index === days.length - 1 ? 1 / 5000 : 0,
      requests: index === days.length - 1 ? 1 : 0,
    }));
    await route.fulfill({ response, json: fixture });
  });
  await page.reload();
  await page.waitForFunction(() => document.querySelector('#balance').textContent === '0.0002');
  assert.equal(await page.locator('#usage-total').textContent(), '0.0002');
  assert.match(await page.locator('#held-balance').textContent(), /^0\.0002 credits reserved/);
  assert.deepEqual(await page.locator('#requests strong').allTextContents(), ['0.0002 credits', '0.0002 reserved']);
  assert.equal(await page.locator('#provider-usage strong').textContent(), '0.0002 credits');
  assert.match(await page.locator('#usage-chart button').last().getAttribute('aria-label'), /0\.0002 credits/);
  assert.match(await page.locator('#usage-chart button').first().getAttribute('aria-label'), /0\.0000 credits/);
  assert.deepEqual(await page.locator('.key-limit-summary .decimal-places').allTextContents(), ['.125', '.75']);
  assert.deepEqual(await page.locator('#history .decimal-places').allTextContents(), ['.25', '.25']);
  await page.locator('#open-purchase').click();
  await page.locator('#amount').fill('5.25');
  assert.equal(await page.locator('#purchase').textContent(), 'Try a $5.25 demo top-up');
  assert.equal(await page.locator('#purchase .decimal-places').textContent(), '.25');
  await page.keyboard.press('Escape');
  await page.locator('.chart-day').last().focus();
  for (const selector of ['#balance', '#usage-total', '#held-balance', '#requests', '#provider-usage', '#chart-y-axis', '#chart-detail', '#purchase', '#history', '.key-limit-summary']) {
    const decimals = page.locator(selector + ' .decimal-places');
    assert.ok(await decimals.count(), `Missing decimal formatting in ${selector}`);
    assert.equal(await decimals.evaluateAll(nodes => nodes.every(node => getComputedStyle(node).opacity === '0.5' && getComputedStyle(node).display === 'inline' && getComputedStyle(node).position === 'static' && getComputedStyle(node).fontSize === getComputedStyle(node.parentElement).fontSize)), true, `Decimal styling in ${selector}`);
  }
  assert.equal(await page.locator('#requests small .decimal-places').count(), 0);
  assert.deepEqual(await page.locator('.detail-content > .decimal-places, #demo-panel > p > .decimal-places').allTextContents(), ['.005', '.01']);
  await page.locator('.period-control button').first().focus();
  for (const width of [320, 375, 768, 1280]) {
    await page.setViewportSize({ width, height: 900 });
    await page.evaluate(() => new Promise(requestAnimationFrame));
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Precision overflow at ${width}px: ${await page.evaluate(() => [...document.querySelectorAll('body *')].filter(el => el.getBoundingClientRect().right > innerWidth).map(el => ({ tag: el.tagName, id: el.id, class: el.className, right: el.getBoundingClientRect().right }))) .then(JSON.stringify)}`);
    for (const column of [page.locator('.chart-day').first(), page.locator('.chart-day').last()]) {
      await column.focus();
      const tooltip = await page.locator('#chart-detail').boundingBox();
      const plot = await page.locator('.chart-wrap').boundingBox();
      assert.ok(tooltip.x >= plot.x && tooltip.x + tooltip.width <= plot.x + plot.width + 1, `Tooltip overflow at ${width}px`);
      assert.equal(await page.locator('#chart-connector').isVisible(), true);
    }

  }
  await page.emulateMedia({ reducedMotion: 'reduce' });
  assert.equal(await page.locator('.chart-bar').first().evaluate(el => getComputedStyle(el).transitionDuration), '0s');
  const signedIn = await (await fetch(config.origin + '/api/account?days=30')).json();
  await page.route('**/api/config', route => route.fulfill({ json: { mode: 'live', clerk: { origin, publishableKey: 'fixture' } } }));
  await page.route('**/api/account?*', route => route.fulfill({ json: { ...signedIn, mode: 'live' } }));
  await page.route('**/npm/@clerk/ui@1/dist/ui.browser.js', route => route.fulfill({ contentType: 'application/javascript', body: 'window.__internal_ClerkUICtor = {};' }));
  await page.route('**/npm/@clerk/clerk-js@6/dist/clerk.browser.js', route => route.fulfill({ contentType: 'application/javascript', body: `
    window.Clerk = {
      user: null, session: null,
      async load(options) { window.clerkOptions = options; },
      addListener(callback) { window.changeUser = callback; },
      mountSignIn(element) { element.textContent = 'Sign-in fixture'; },
      unmountSignIn(element) { element.textContent = ''; },
      mountUserButton() {}
    };
  ` }));
  await page.goto(origin + '/#keys-details');
  await page.locator('#sign-in').waitFor({ state: 'visible' });
  assert.equal(await page.locator('#account-content').isVisible(), false);
  await page.evaluate(() => window.changeUser({ user: { id: 'fixture-owner' } }));
  await page.locator('#account-content').waitFor({ state: 'visible' });
  assert.equal(await page.locator('#keys-details').evaluate(el => el.open), true);
  assert.equal(await page.locator('#mode-badge').isVisible(), false);
  assert.doesNotMatch(await page.locator('#purchase').textContent(), /[\u2190-\u21ff]/);
  assert.equal(await page.locator('#footer-mode').isVisible(), false);
  assert.equal(await page.evaluate(() => window.clerkOptions.telemetry), false);
  await page.locator('#open-purchase').click();
  await page.evaluate(() => window.changeUser({ user: null }));
  await page.locator('#account-content').waitFor({ state: 'hidden' });
  assert.equal(await page.locator('#purchase-dialog').isVisible(), false);
  for (const id of ['balance', 'usage-chart', 'key-list', 'requests']) assert.equal(await page.locator('#' + id).textContent(), '');
  assert.deepEqual(errors, []);
  console.log(
    "PASS: arrow-free credit actions, bundled brand font, proportional stroke chart, periods, empty state, exact usage, device attribution, keyboard controls, reduced motion, responsive layout; demo purchases, key issuance/revocation, pairing, signed-in limits link and sign-out clearing. No screenshots or clipboard access.",
  );
} finally {
  await browser.close();
  await app.close();
}
