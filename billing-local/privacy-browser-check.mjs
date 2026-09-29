import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { once } from 'node:events';
import { createApplication } from './server.mjs';
import { configuration } from './config.mjs';

const config = configuration({ S2T_BILLING_DATA_DIR: mkdtempSync(tmpdir() + '/s2t-privacy-') });
const app = createApplication(config);
app.server.listen(0, '127.0.0.1');
await once(app.server, 'listening');
config.port = app.server.address().port;
config.origin = `http://localhost:${config.port}`;
const browser = await chromium.launch({ channel: 'chrome', headless: true });
try {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(config.origin);
  await page.waitForFunction(() => !document.querySelector('#account-content').hidden);
  const links = await page.locator('footer nav a').evaluateAll(nodes => nodes.map(node => node.getAttribute('href')));
  assert.equal(links.length, 6);
  await page.locator('#open-purchase').click();
  for (const slug of ['privacy', 'terms', 'refunds']) assert.equal(await page.locator(`#purchase-dialog a[href="/policies/${slug}.html"]`).isVisible(), true);
  const requests = [];
  page.on('request', request => requests.push(request.url()));
  for (const link of links) {
    requests.length = 0;
    const response = await page.goto(config.origin + link);
    assert.equal(response.status(), 200);
    assert.equal(await page.locator('main h1').count(), 1);
    assert.equal(await page.locator('nav [aria-current="page"]').count(), 1);
    assert.equal(await page.locator('script').count(), 0);
    assert.equal(await page.locator('a[href="mailto:info@conrad-baulig.com"]').count(), 1);
    for (const width of [320, 768, 1280]) {
      await page.setViewportSize({ width, height: 900 });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `${link} overflow at ${width}px`);
    }
    assert.ok(requests.every(url => url.startsWith(config.origin + '/policies/')), 'Policy must not call analytics, sign-in, or third parties');
    assert.equal(readFileSync('../website/public' + link, 'utf8'), readFileSync('public' + link, 'utf8'));
  }
  await page.route('**/api/config', route => route.fulfill({ json: { mode: 'test', clerk: { origin: config.origin, publishableKey: 'fixture' } } }));
  await page.route('**/npm/@clerk/ui@1/dist/ui.browser.js', route => route.fulfill({ contentType: 'text/javascript', body: 'window.__internal_ClerkUICtor = {};' }));
  await page.route('**/npm/@clerk/clerk-js@6/dist/clerk.browser.js', route => route.fulfill({ contentType: 'text/javascript', body: 'window.Clerk = { load: async options => { window.fixtureClerkOptions = options; }, addListener() {}, mountSignIn() {} };' }));
  await page.goto(config.origin);
  await page.waitForFunction(() => window.fixtureClerkOptions);
  assert.equal(await page.evaluate(() => window.fixtureClerkOptions.telemetry), false);
  assert.deepEqual(errors, []);
  console.log('PASS: six accessible policy pages, mobile layout, checkout links, identical site copies, no third-party page requests, and Clerk telemetry disabled. Synthetic data only; no screenshots.');
} finally { await browser.close(); await app.close(); }
