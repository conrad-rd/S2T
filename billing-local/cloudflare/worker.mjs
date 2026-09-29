import { createGuestPurchases, recoveryMailer, guestCookie, guestToken } from '../guest-purchases.mjs';
import {createOpenRouterCatalog} from "../openrouter-catalog.mjs";
import { createWithdrawals } from '../withdrawals.mjs';
import { modelCatalog } from "../policy.mjs";
import { operate } from './operator.mjs';
import { requestDevice } from '../usage.mjs';
import { DurableObject } from 'cloudflare:workers';
import { createLedger } from '../ledger-core.mjs';
import { durableDatabase } from './storage.mjs';
import { workerConfiguration } from './config.mjs';
import { requireFreshFundingReview } from '../config-core.mjs';
import { createIdentity } from '../identity.mjs';
import { createDeviceLink } from '../device-link.mjs';
import { createStripeBilling } from '../stripe-billing.mjs';
import { createGateway } from '../gateway.mjs';
import { fixtureClient, providerClient } from '../providers.mjs';
import { checkProviderAccess } from '../provider-access.mjs';
import { Fault, requireThat } from '../money.mjs';

function headers(config) {
  return {
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': `default-src 'self'; script-src 'self' ${config.clerk.origin} https://challenges.cloudflare.com; style-src 'self' 'unsafe-inline'; connect-src 'self' ${config.clerk.origin} https://*.protect.clerk.com:*; img-src 'self' https://img.clerk.com data:; frame-src ${config.clerk.origin} https://challenges.cloudflare.com https://*.protect.clerk.com; worker-src 'self' blob:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`
  };
}
function failure(error) {
  if (/Exceeded allowed rows (?:written|read) in Durable Objects free tier/i.test(error?.message || '')) {
    console.error('S2T billing storage quota exceeded.');
    error = new Fault('storage_quota', 'S2T billing has reached its hosting database limit. Please retry after service is restored.', 503);
  }
  const known = error instanceof Fault;
  return Response.json({ error: known ? error.message : error instanceof SyntaxError ? 'Invalid JSON.' : 'Service unavailable. No new provider request will be sent without a confirmed reservation.', code: known ? error.code : 'unavailable' }, { status: known ? error.status : error instanceof SyntaxError ? 400 : 503, headers: { 'Cache-Control': 'no-store' } });
}
async function body(request, limit, timeoutMs = 45000) {
  requireThat(Number(request.headers.get('content-length') || 0) <= limit, 'body_limit', 'Request body is too large.', 413);
  if (!request.body) return Buffer.alloc(0);
  const reader = request.body.getReader(), chunks = [];
  let timer;
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Fault('upload_timeout', 'Request upload timed out. Retry the upload.', 408)), timeoutMs);
  });
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await Promise.race([reader.read(), deadline]);
      if (done) break;
      size += value.byteLength;
      requireThat(size <= limit, 'body_limit', 'Request body is too large.', 413);
      chunks.push(value);
    }
  } catch (error) { void reader.cancel().catch(() => {}); throw error; }
  finally { clearTimeout(timer); }
  return Buffer.concat(chunks);
}
export class CreditsLedger extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.config = workerConfiguration(env);
    this.ledger = createLedger(durableDatabase(ctx.storage), { mode: this.config.mode, enforceReconciliation: this.config.realProviders, fundingReviewedAt: this.config.fundingReviewedAt ?? null });
    this.ledger.recover();
    ctx.blockConcurrencyWhile(async () => {
      this.ledger.purgeExpired();
      if (await ctx.storage.getAlarm() === null) await ctx.storage.setAlarm(Date.now() + 60000);
    });
    this.identity = createIdentity(this.config.identity);
    this.devices = createDeviceLink({ ledger: this.ledger, mode: this.config.mode, encryptionKey: this.config.resultKey, origin: this.config.browserOrigin });
    this.guests = createGuestPurchases({ ledger: this.ledger, mode: this.config.mode, encryptionKey: this.config.resultKey, credentialKey: this.config.guestCredentialKey, origin: this.config.browserOrigin, sendEmail: recoveryMailer(env.S2T_RECOVERY_EMAIL_KEY, env.S2T_RECOVERY_EMAIL_FROM), confirmSaved: () => ctx.storage.sync() });
    this.billing = createStripeBilling({ ledger: this.ledger, mode: this.config.mode, secret: this.config.webhookSecret, apiKey: this.config.stripeKey, origin: this.config.browserOrigin, onFulfilled: session => this.guests.fulfilled(session) });
    this.modelCatalog = createOpenRouterCatalog({policy:this.config.policy,enabled:this.config.realProviders});
    this.gateway = createGateway({ ledger: this.ledger, policy: this.config.policy, resolvePolicy: body => this.modelCatalog.policyFor(body), execute: this.config.realProviders ? providerClient({ keys: this.config.keys }) : fixtureClient(), encryptionKey: this.config.resultKey, confirmReservation: () => ctx.storage.sync() });
    this.operatorKey = env.S2T_OPERATOR_KEY;
    this.withdrawals = createWithdrawals({ledger:this.ledger,encryptionKey:this.config.resultKey,confirmSaved:()=>ctx.storage.sync()});
    this.uploads = 0;
  }
  async alarm() {
    this.ledger.purgeExpired();
    await this.ctx.storage.setAlarm(Date.now() + 60000);
  }
  async providerReady() {
    if (!this.config.realProviders) return false;
    requireFreshFundingReview(this.config);
    if (!this.providerCheckedAt || Date.now() - this.providerCheckedAt > 60000) {
      this.providerCheck ??= checkProviderAccess(this.config.keys).then(() => {
        this.providerCheckedAt = Date.now();
      }).finally(() => { this.providerCheck = null; });
      await this.providerCheck;
    }
    return true;
  }
  allowed(account) { requireThat(!this.config.allowedAccounts || this.config.allowedAccounts.includes(account), 'staging_access', 'This service is restricted to approved testers.', 403); }
  rate(id, count, interval) { requireThat(this.ledger.rate(id, count, interval), 'rate_limit', 'Request limit reached. Try again shortly.', 429); }
  key(request) {
    const raw = request.headers.get('authorization') || '';
    requireThat(raw.startsWith('Bearer '), 'authentication', 'Provide an S2T app key.', 401);
    const key = this.ledger.authenticate(raw.slice(7));
    requireThat(key, 'authentication', 'App key is invalid, expired, or revoked.', 401);
    if (!this.ledger.guests.get(key.account)) this.allowed(key.account);
    return key;
  }
  async account(request) {
    const raw = request.headers.get('authorization') || '';
    requireThat(raw.startsWith('Bearer '), 'authentication', 'Sign in to your S2T account.', 401);
    let subject;
    try { subject = await this.identity(raw.slice(7)); }
    catch { throw new Fault('authentication', 'Account authentication failed.', 401); }
    const account = this.ledger.identity(subject);
    this.allowed(account.id);
    return account;
  }
  async read(request, limit = 4096) {
    requireThat(this.uploads < 4, 'busy', 'Too many uploads.', 429);
    this.uploads++;
    try { return await body(request, limit); } finally { this.uploads--; }
  }
  async fetch(request) {
    const started = performance.now();
    try {
      const url = new URL(request.url), path = url.pathname, method = request.method, config = this.config;
      requireThat(url.origin === config.origin, 'host', 'Invalid host.', 403);
      if (method === 'GET' && path === '/health') {
        const paused = this.ctx.storage.sql.exec("SELECT value FROM metadata WHERE key='paused'").one().value === '1';
        return Response.json({ status: paused ? 'paused' : 'ok', storage: 'durable-sqlite', mode: config.mode }, { status: paused ? 503 : 200, headers: headers(config) });
      }
      const ip = request.headers.get('cf-connecting-ip') || 'unknown';
      const apiKey = path.startsWith('/api/v1/') ? this.key(request) : null;
      this.rate('ip:' + ip, 300);
      const json = data => Response.json(data, { headers: { ...headers(config), 'Server-Timing': `ledger;dur=${(performance.now() - started).toFixed(1)}` } });
      if (method === 'POST' && path === '/api/operator') {
        const result = operate(this.ledger, this.operatorKey, request.headers.get('authorization'), JSON.parse((await this.read(request)).toString()), this.config.policy, this.withdrawals, this.guests);
        await this.ctx.storage.sync();
        return json(result);
      }
      if (method === 'POST' && ['/api/device/start', '/api/device/poll'].includes(path)) {
        requireThat(!request.headers.get('origin') || request.headers.get('origin') === config.browserOrigin, 'origin', 'Invalid origin.', 403);
        if (path.endsWith('/start')) { this.rate('device-start:' + ip, 10); return json(this.devices.start()); }
        this.rate('device-poll:' + ip, 90);
        return json(this.devices.poll(JSON.parse((await this.read(request)).toString()).deviceCode));
      }
      if (method === 'POST' && path === '/api/stripe/webhook') return json(await this.billing.webhook(await this.read(request, 1000000), request.headers.get('stripe-signature')));
      if (path.startsWith('/api/v1/')) {
        const key = apiKey;
        this.rate('key:' + key.id, 300);
        if (method === 'GET' && path === '/api/v1/warm') return json({ ready: true });
        if (method === 'GET' && path === '/api/v1/providers') return json({ ready: await this.providerReady() });
        if (method === 'GET' && path === '/api/v1/balance') return json({ ...this.ledger.summary(key.account), mode: config.mode, realProviders: config.realProviders, openRouterCatalog: config.realProviders, models: await this.modelCatalog.models(), keyLimit: this.ledger.keyLimits(key.account, key.id) });
        const match = /^\/api\/v1\/requests\/([a-f0-9-]{36})(\/cancel)?$/.exec(path);
        if (match && method === 'GET' && !match[2]) return json(this.gateway.get(key.account, match[1]));
        if (match && method === 'POST' && match[2]) return json(this.gateway.cancel(key.account, match[1]));
        if (method === 'POST' && path === '/api/v1/requests') {
          const reading = performance.now(), timings = {};
          const value = JSON.parse((await this.read(request, 12000000)).toString());
          timings.upload = performance.now() - reading;
          const operation = this.gateway.run({ account: key.account, keyId: key.id, device: requestDevice(request.headers.get('x-s2t-device-id'), request.headers.get('x-s2t-device-name')), idempotencyKey: request.headers.get('idempotency-key'), body: value, timings });
          this.ctx.waitUntil(operation);
          const result = await operation;
          timings.ledger = performance.now() - started;
          return Response.json(result, { status: result.state === 'settled' ? 200 : 202, headers: { ...headers(config), 'Server-Timing': Object.entries(timings).map(([name, ms]) => `${name};dur=${ms.toFixed(1)}`).join(', ') } });
        }
        throw new Fault('not_found', 'Endpoint not found.', 404);
      }
      if (method === 'POST' && path === '/api/withdrawals') {
        requireThat(request.headers.get('origin')===config.browserOrigin,'origin','Invalid origin.',403);
        this.rate('withdrawal:'+request.headers.get('cf-connecting-ip'),10);
        return json(await this.withdrawals.submit(JSON.parse((await this.read(request)).toString())));
      }
      if (path.startsWith('/api/guest/')) {
        requireThat(request.headers.get('origin') === config.browserOrigin || method === 'GET', 'origin', 'Invalid origin.', 403);
        this.rate('guest:' + ip, 60);
        const token = guestToken(request);
        const withCookie = async result => {
          await this.ctx.storage.sync();
          const response = json({ remembered: true });
          response.headers.set('Set-Cookie', guestCookie(result.token));
          return response;
        };
        if (method === 'GET' && path === '/api/guest/status') return json(this.guests.status(token));
        requireThat(method === 'POST', 'method', 'Use POST.', 405);
        const value = JSON.parse((await this.read(request)).toString() || '{}');
        if (path === '/api/guest/recover') { this.rate('guest-recover:' + ip, 10); return withCookie(this.guests.recover(value.code, value.emailLink === true)); }
        if (path === '/api/guest/email') { this.rate('guest-email-ip:' + ip, 5, 3600000); return json(await this.guests.requestEmail(value.email)); }
        requireThat(config.guestCheckout && config.stripeKey && config.webhookSecret, 'guest_disabled', 'Guest checkout is not available yet.', 503);
        if (path === '/api/guest/start') { this.rate('guest-start:' + ip, 10, 3600000); return withCookie(this.guests.start(token)); }
        if (path === '/api/guest/checkout') {
          this.rate('guest-checkout:' + ip, 10);
          const row = this.guests.checkoutAccount(token, value.recoveryCode);
          requireThat(typeof value.emailRecovery === 'boolean', 'email', 'Choose whether to enable email recovery.');
          requireThat(!value.emailRecovery || config.guestEmailRecovery, 'email_disabled', 'Email recovery is not available yet.', 503);
          await this.providerReady();
          this.ledger.guests.optIn(row.account, value.emailRecovery);
          return json(await this.billing.checkout(row.account, value.cents, request.headers.get('idempotency-key'), { guest: true }));
        }
        throw new Fault('not_found', 'Endpoint not found.', 404);
      }
      const account = await this.account(request);
      if (method === 'GET' && path === '/api/providers') return json({ ready: await this.providerReady() });
      if (method === 'GET' && path === '/api/account') return json({ ...this.ledger.summary(account.id), usage: this.ledger.usage(account.id, Number(url.searchParams.get('days') ?? 30)), mode: config.mode, realProviders: config.realProviders, checkoutEnabled: !!config.stripeKey && !!config.webhookSecret, limits: this.ledger.limits });
      if (method === 'POST') {
        requireThat(request.headers.get('origin') === config.browserOrigin, 'origin', 'Invalid origin.', 403);
        const value = JSON.parse((await this.read(request)).toString() || '{}');
        if (path === '/api/device/approve') return json(this.devices.approve(account.id, value.userCode));
        if (path === '/api/keys') return json(this.ledger.issueKey(account.id, value));
        if (path === '/api/keys/limits') { const { id, ...limits } = value; return json(this.ledger.setKeyLimits(account.id, id, limits)); }
        if (path === '/api/keys/revoke') { this.ledger.revoke(account.id, value.id); return json({ revoked: true }); }
        if (path === '/api/checkout') {
          this.rate('checkout:' + account.id, 10);
          requireThat(config.stripeKey && config.webhookSecret, 'checkout_disabled', 'Checkout is not configured yet.', 503);
          await this.providerReady();
          return json(await this.billing.checkout(account.id, value.cents, request.headers.get('idempotency-key')));
        }
      }
      throw new Fault('not_found', 'Endpoint not found.', 404);
    } catch (error) { return failure(error); }
  }
}
export default {
  async fetch(request, env) {
    try {
      const config = workerConfiguration(env), url = new URL(request.url);
      requireThat(url.origin === config.origin, 'host', 'Invalid host.', 403);
      if (request.method === 'GET' && url.pathname === '/api/config') return Response.json({ mode: config.mode, realProviders: config.realProviders, clerk: config.clerk, guestCheckout: config.guestCheckout, guestEmailRecovery: config.guestEmailRecovery }, { headers: headers(config) });
      if (url.pathname.startsWith('/api/') || request.method === 'GET' && url.pathname === '/health') {
        const started = performance.now();
        const response = await env.CREDITS.get(env.CREDITS.idFromName('s2t-credits-' + config.mode)).fetch(request);
        const measured = new Response(response.body, response);
        measured.headers.append('Server-Timing', `edge;dur=${(performance.now() - started).toFixed(1)}`);
        return measured;
      }
      if (config.browserOrigin !== config.origin) return Response.redirect(config.browserOrigin + url.pathname + url.search, 302);
      const asset = await env.ASSETS.fetch(request);
      const response = new Response(asset.body, asset);
      for (const [key, value] of Object.entries(headers(config))) response.headers.set(key, value);
      return response;
    } catch (error) { return failure(error); }
  }
};
