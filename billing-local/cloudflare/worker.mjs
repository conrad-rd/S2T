import { DurableObject } from 'cloudflare:workers';
import { createLedger } from '../ledger-core.mjs';
import { durableDatabase } from './storage.mjs';
import { workerConfiguration } from './config.mjs';
import { createIdentity } from '../identity.mjs';
import { createDeviceLink } from '../device-link.mjs';
import { createStripeBilling } from '../stripe-billing.mjs';
import { createGateway } from '../gateway.mjs';
import { fixtureClient, providerClient } from '../providers.mjs';
import { Fault, requireThat } from '../money.mjs';

function headers(config) {
  return {
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': `default-src 'self'; script-src 'self' ${config.clerk.origin} https://challenges.cloudflare.com; style-src 'self' 'unsafe-inline'; connect-src 'self' ${config.clerk.origin}; img-src 'self' https://img.clerk.com data:; frame-src ${config.clerk.origin} https://challenges.cloudflare.com; worker-src 'self' blob:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`
  };
}
function failure(error) {
  const known = error instanceof Fault;
  return Response.json({ error: known ? error.message : error instanceof SyntaxError ? 'Invalid JSON.' : 'Service unavailable. No new provider request will be sent without a confirmed reservation.', code: known ? error.code : 'unavailable' }, { status: known ? error.status : error instanceof SyntaxError ? 400 : 503, headers: { 'Cache-Control': 'no-store' } });
}
async function body(request, limit) {
  requireThat(Number(request.headers.get('content-length') || 0) <= limit, 'body_limit', 'Request body is too large.', 413);
  if (!request.body) return Buffer.alloc(0);
  const reader = request.body.getReader(), chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      requireThat(size <= limit, 'body_limit', 'Request body is too large.', 413);
      chunks.push(value);
    }
  } catch (error) { await reader.cancel(); throw error; }
  return Buffer.concat(chunks);
}
export class CreditsLedger extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.config = workerConfiguration(env);
    this.ledger = createLedger(durableDatabase(ctx.storage), { mode: this.config.mode });
    this.ledger.recover();
    this.identity = createIdentity(this.config.identity);
    this.devices = createDeviceLink({ ledger: this.ledger, mode: this.config.mode, encryptionKey: this.config.resultKey, origin: this.config.origin });
    this.billing = createStripeBilling({ ledger: this.ledger, mode: this.config.mode, secret: this.config.webhookSecret, apiKey: this.config.stripeKey, origin: this.config.origin });
    this.gateway = createGateway({ ledger: this.ledger, policy: this.config.policy, execute: this.config.realProviders ? providerClient({ keys: this.config.keys }) : fixtureClient(), encryptionKey: this.config.resultKey, confirmReservation: () => ctx.storage.sync() });
    this.uploads = 0;
  }
  allowed(account) { requireThat(!this.config.allowedAccounts || this.config.allowedAccounts.includes(account), 'staging_access', 'This service is restricted to approved testers.', 403); }
  rate(id, count, interval) { requireThat(this.ledger.rate(id, count, interval), 'rate_limit', 'Request limit reached. Try again shortly.', 429); }
  key(request) {
    const raw = request.headers.get('authorization') || '';
    requireThat(raw.startsWith('Bearer '), 'authentication', 'Provide an S2T app key.', 401);
    const key = this.ledger.authenticate(raw.slice(7));
    requireThat(key, 'authentication', 'App key is invalid, expired, or revoked.', 401);
    this.allowed(key.account);
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
    try {
      const url = new URL(request.url), path = url.pathname, method = request.method, config = this.config;
      requireThat(url.origin === config.origin, 'host', 'Invalid host.', 403);
      const ip = request.headers.get('cf-connecting-ip') || 'unknown';
      this.rate('ip:' + ip, 300);
      const json = data => Response.json(data, { headers: headers(config) });
      if (method === 'POST' && ['/api/device/start', '/api/device/poll'].includes(path)) {
        requireThat(!request.headers.get('origin') || request.headers.get('origin') === config.origin, 'origin', 'Invalid origin.', 403);
        if (path.endsWith('/start')) { this.rate('device-start:' + ip, 10); return json(this.devices.start()); }
        this.rate('device-poll:' + ip, 90);
        return json(this.devices.poll(JSON.parse((await this.read(request)).toString()).deviceCode));
      }
      if (method === 'POST' && path === '/api/stripe/webhook') return json(await this.billing.webhook(await this.read(request, 1000000), request.headers.get('stripe-signature')));
      if (path.startsWith('/api/v1/')) {
        const key = this.key(request);
        this.rate('key:' + key.id, 60);
        if (method === 'GET' && path === '/api/v1/balance') return json({ ...this.ledger.summary(key.account), mode: config.mode, realProviders: config.realProviders });
        const match = /^\/api\/v1\/requests\/([a-f0-9-]{36})(\/cancel)?$/.exec(path);
        if (match && method === 'GET' && !match[2]) return json(this.gateway.get(key.account, match[1]));
        if (match && method === 'POST' && match[2]) return json(this.gateway.cancel(key.account, match[1]));
        if (method === 'POST' && path === '/api/v1/requests') {
          requireThat(!config.realProviders || config.externalControlsExpire > Date.now(), 'controls_expired', 'Provider spending controls need review.', 503);
          const value = JSON.parse((await this.read(request, 12000000)).toString());
          const operation = this.gateway.run({ account: key.account, keyId: key.id, idempotencyKey: request.headers.get('idempotency-key'), body: value });
          this.ctx.waitUntil(operation);
          const result = await operation;
          return Response.json(result, { status: result.state === 'settled' ? 200 : 202, headers: headers(config) });
        }
        throw new Fault('not_found', 'Endpoint not found.', 404);
      }
      const account = await this.account(request);
      if (method === 'GET' && path === '/api/account') return json({ ...this.ledger.summary(account.id), mode: config.mode, realProviders: config.realProviders, checkoutEnabled: !!config.stripeKey && !!config.webhookSecret, limits: this.ledger.limits });
      if (method === 'POST') {
        requireThat(request.headers.get('origin') === config.origin, 'origin', 'Invalid origin.', 403);
        const value = JSON.parse((await this.read(request)).toString() || '{}');
        if (path === '/api/device/approve') return json(this.devices.approve(account.id, value.userCode));
        if (path === '/api/keys') return json(this.ledger.issueKey(account.id));
        if (path === '/api/keys/revoke') { this.ledger.revoke(account.id, value.id); return json({ revoked: true }); }
        if (path === '/api/checkout') {
          this.rate('checkout:' + account.id, 10);
          requireThat(config.stripeKey && config.webhookSecret, 'checkout_disabled', 'Checkout is not configured yet.', 503);
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
      if (request.method === 'GET' && url.pathname === '/health') return Response.json({ status: 'ok', storage: 'durable-sqlite', mode: config.mode });
      if (request.method === 'GET' && url.pathname === '/api/config') return Response.json({ mode: config.mode, realProviders: config.realProviders, clerk: config.clerk }, { headers: headers(config) });
      if (url.pathname.startsWith('/api/')) return env.CREDITS.get(env.CREDITS.idFromName('s2t-credits-' + config.mode)).fetch(request);
      const asset = await env.ASSETS.fetch(request);
      const response = new Response(asset.body, asset);
      for (const [key, value] of Object.entries(headers(config))) response.headers.set(key, value);
      return response;
    } catch (error) { return failure(error); }
  }
};
