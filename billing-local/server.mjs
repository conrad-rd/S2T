import { createServer } from "node:http";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { randomUUID, randomBytes } from "node:crypto";
import { fileURLToPath } from "node:url";
import { configuration } from "./config.mjs";
import { openLedger } from "./ledger.mjs";
import { createGateway } from "./gateway.mjs";
import { fixtureClient, providerClient } from "./providers.mjs";
import { createStripeBilling } from "./stripe-billing.mjs";
import { createIdentity } from "./identity.mjs";
import { Fault, requireThat } from "./money.mjs";
export function createApplication(config, { execute, stripeClient } = {}) {
  mkdirSync(config.dataDir, { recursive: true, mode: 0o700 });
  const ledger = openLedger(config.dataDir + `/${config.mode}-ledger.sqlite`, {
    mode: config.mode,
  });
  ledger.claim();
  ledger.recover();
  let encryptionKey = config.resultKey;
  if (!encryptionKey) {
    const path = config.dataDir + `/${config.mode}-result.key`;
    try {
      encryptionKey = readFileSync(path);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
      encryptionKey = randomBytes(32);
      writeFileSync(path, encryptionKey, { mode: 0o600, flag: "wx" });
    }
  }
  const gateway = createGateway({
    ledger,
    policy: config.policy,
    execute:
      execute || (config.mode === "live" ? providerClient({ keys: config.keys }) : fixtureClient()),
    encryptionKey,
  });
  const identity = createIdentity(config.identity);
  const billing = createStripeBilling({
    ledger,
    mode: config.mode,
    secret: config.webhookSecret,
    paymentLinkId: config.paymentLinkId,
    apiKey: config.stripeKey,
    stripeClient,
    paymentLinkURL: config.paymentLink,
  });
  const publicRoot = fileURLToPath(new URL("./public/", import.meta.url));
  const files = {
    "/": ["index.html", "text/html"],
    "/app.js": ["app.js", "text/javascript"],
    "/style.css": ["style.css", "text/css"],
    "/s2t.svg": ["s2t.svg", "image/svg+xml"],
    ...Object.fromEntries(
      [400, 500, 600].map((weight) => [
        `/fonts/manrope-${weight}.ttf`,
        [`fonts/manrope-${weight}.ttf`, "font/ttf"],
      ]),
    ),
  };
  let readingBodies = 0;
  async function readBody(req, max) {
    requireThat(readingBodies < 8, "busy", "Too many uploads. Try again shortly.", 429);
    readingBodies++;
    try {
      let size = 0;
      const parts = [];
      for await (const part of req) {
        size += part.length;
        requireThat(size <= max, "body_limit", "Request body is too large.", 413);
        parts.push(part);
      }
      return Buffer.concat(parts);
    } finally {
      readingBodies--;
    }
  }
  function origin(req) {
    requireThat(
      [
        config.origin,
        ...(config.mode === "live" ? [] : [`http://127.0.0.1:${config.port}`]),
      ].includes(req.headers.origin),
      "origin",
      "Invalid request origin.",
      403,
    );
  }
  async function account(req, res, { create = false } = {}) {
    if (config.mode === "live") {
      const token = req.headers.authorization?.replace(/^Bearer /, "");
      requireThat(
        token && identity,
        "authentication",
        "Sign in with the configured identity provider.",
        401,
      );
      try {
        return ledger.identity(await identity(token));
      } catch {
        throw new Fault("authentication", "Account authentication failed.", 401);
      }
    }
    const token =
      req.headers.cookie
        ?.split(";")
        .map((v) => v.trim())
        .find((v) => v.startsWith("s2t_session="))
        ?.slice(12) || "";
    const existing = ledger.session(token);
    if (existing) return existing;
    requireThat(create, "authentication", "Open the dashboard to start a session.", 401);
    requireThat(
      ledger.rate(`sessions:${req.socket.remoteAddress}`, 30, 3600000),
      "rate_limit",
      "Session creation limit reached.",
      429,
    );
    const session = ledger.createSession();
    res.setHeader(
      "Set-Cookie",
      `s2t_session=${session.token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=604800`,
    );
    return { id: session.account };
  }
  function key(req) {
    const raw = req.headers.authorization;
    requireThat(
      typeof raw === "string" && raw.startsWith("Bearer "),
      "authentication",
      "Provide an S2T API key.",
      401,
    );
    const key = ledger.authenticate(raw.slice(7));
    requireThat(key, "authentication", "API key is invalid, expired, or revoked.", 401);
    return key;
  }
  const server = createServer(async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Referrer-Policy", "no-referrer");
    res.setHeader(
      "Content-Security-Policy",
      "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
    );
    const json = (status, data) => {
      if (!res.destroyed) {
        res.writeHead(status, { "Content-Type": "application/json" });
        res.end(JSON.stringify(data));
      }
    };
    try {
      const hosts = [
        new URL(config.origin).host,
        ...(config.mode === "live" ? [] : [`127.0.0.1:${config.port}`]),
      ];
      requireThat(hosts.includes(req.headers.host), "host", "Invalid host.", 403);
      const path = new URL(req.url, config.origin).pathname;
      if (req.method === "GET" && Object.hasOwn(files, path)) {
        const [file, type] = files[path];
        res.writeHead(200, { "Content-Type": type });
        return res.end(readFileSync(publicRoot + file));
      }
      requireThat(
        ledger.rate(`ip:${req.socket.remoteAddress}`, 300),
        "rate_limit",
        "Request limit reached.",
        429,
      );
      if (req.method === "POST" && path === "/api/stripe/webhook") {
        const raw = await readBody(req, 1000000);
        return json(200, await billing.webhook(raw, req.headers["stripe-signature"]));
      }
      if (path.startsWith("/api/v1/")) {
        const authenticated = key(req);
        requireThat(
          ledger.rate(`key:${authenticated.id}`, 60),
          "rate_limit",
          "API key request limit reached.",
          429,
        );
        if (req.method === "GET" && path === "/api/v1/balance")
          return json(200, ledger.summary(authenticated.account));
        const match = /^\/api\/v1\/requests\/([a-f0-9-]{36})(\/cancel)?$/.exec(path);
        if (match && req.method === "GET" && !match[2])
          return json(200, gateway.get(authenticated.account, match[1]));
        if (match && req.method === "POST" && match[2])
          return json(200, gateway.cancel(authenticated.account, match[1]));
        if (req.method === "POST" && path === "/api/v1/requests") {
          requireThat(
            config.mode !== "live" || config.externalControlsExpire > Date.now(),
            "controls_expired",
            "Provider spending controls need operator review.",
            503,
          );
          const body = JSON.parse((await readBody(req, 12000000)).toString());
          const result = await gateway.run({
            account: authenticated.account,
            keyId: authenticated.id,
            idempotencyKey: req.headers["idempotency-key"],
            body,
          });
          return json(result.state === "settled" ? 200 : 202, result);
        }
        throw new Fault("not_found", "Endpoint not found.", 404);
      }
      const a = await account(req, res, {
        create: req.method === "GET" && path === "/api/account",
      });
      if (req.method === "GET" && path === "/api/account")
        return json(200, {
          ...ledger.summary(a.id),
          mode: config.mode,
          paymentLink: config.paymentLink,
          checkoutReference: a.id,
          limits: ledger.limits,
        });
      if (req.method === "POST") {
        origin(req);
        const body = JSON.parse((await readBody(req, 4096)).toString() || "{}");
        if (path === "/api/demo/purchase") {
          requireThat(config.mode === "demo", "demo_disabled", "Demo top-ups are disabled.", 404);
          const reference = "demo_" + randomUUID();
          ledger.grant({ account: a.id, cents: body.cents, session: reference, intent: reference });
          return json(200, ledger.summary(a.id));
        }
        if (path === "/api/demo/request") {
          requireThat(config.mode === "demo", "demo_disabled", "Demo requests are disabled.", 404);
          const result = await gateway.run({
            account: a.id,
            idempotencyKey: req.headers["idempotency-key"],
            body: {
              provider: "openrouter",
              operation: "cleanup",
              text: "A synthetic request to verify credit accounting.",
            },
          });
          return json(200, result);
        }
        if (path === "/api/keys") return json(200, ledger.issueKey(a.id));
        if (path === "/api/keys/revoke") {
          ledger.revoke(a.id, body.id);
          return json(200, { revoked: true });
        }
        if (path === "/api/checkout") {
          requireThat(
            config.mode === "live" && config.paymentLinkId,
            "checkout_disabled",
            "Live checkout is not enabled.",
            503,
          );
          return json(200, await billing.checkout(a.id));
        }
      }
      throw new Fault("not_found", "Endpoint not found.", 404);
    } catch (error) {
      if (error instanceof Fault) json(error.status, { error: error.message, code: error.code });
      else if (error instanceof SyntaxError) json(400, { error: "Invalid JSON.", code: "json" });
      else {
        console.error("Request failed; operation was not acknowledged.");
        json(503, {
          error:
            "Service unavailable. No new request will be sent without a confirmed reservation.",
          code: "unavailable",
        });
      }
    }
  });
  server.requestTimeout = 45000;
  server.headersTimeout = 15000;
  server.maxConnections = 100;
  return {
    server,
    ledger,
    close: () =>
      new Promise((resolve) =>
        server.close(() => {
          ledger.unclaim();
          ledger.close();
          resolve();
        }),
      ),
  };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const config = configuration();
  const app = createApplication(config);
  app.server.listen(config.port, "127.0.0.1", () =>
    console.log(
      `S2T Credits: http://localhost:${config.port} (${config.mode}; ${config.mode === "live" ? "bounded provider access" : "no real provider spending"})`,
    ),
  );
  let closing = false;
  const shutdown = () => {
    if (closing) return;
    closing = true;
    app.close().then(() => process.exit(0));
    setTimeout(() => process.exit(1), 35000).unref();
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}
