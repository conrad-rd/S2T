import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { prepareRequest } from "./policy.mjs";
import { ProviderRejected } from "./providers.mjs";
import { requireThat, Fault, credits } from "./money.mjs";
function requestBodyHash(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  try {
    const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
      ? Object.fromEntries(Object.keys(value).sort().map(key => [key,canonical(value[key])])) : value;
    return createHash('sha256').update('s2t-request-body-v1:').update(JSON.stringify(canonical(body))).digest('hex');
  } catch { return null; }
}
function legacySpeechFingerprint(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || body.operation !== 'transcription' ||
      typeof body.provider !== 'string' || typeof body.model !== 'string' || typeof body.audio !== 'string' ||
      Object.keys(body).sort().join(',') !== 'audio,model,operation,provider') return null;
  return createHash('sha256').update(JSON.stringify([body.provider,body.operation,body.model,body.audio,null])).digest('hex');
}
export function createGateway({ ledger, policy, execute, encryptionKey, confirmReservation = async () => {}, resolvePolicy = async () => policy }) {
  requireThat(
    Buffer.isBuffer(encryptionKey) && encryptionKey.length === 32,
    "config",
    "A 256-bit result encryption key is required.",
  );
  const encrypt = (id, value) => {
    const iv = randomBytes(12),
      cipher = createCipheriv("aes-256-gcm", encryptionKey, iv);
    cipher.setAAD(Buffer.from(id));
    const data = Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), data]).toString("base64");
  };
  const decrypt = (id, value) => {
    const data = Buffer.from(value, "base64"),
      cipher = createDecipheriv("aes-256-gcm", encryptionKey, data.subarray(0, 12));
    cipher.setAAD(Buffer.from(id));
    cipher.setAuthTag(data.subarray(12, 28));
    return JSON.parse(Buffer.concat([cipher.update(data.subarray(28)), cipher.final()]).toString());
  };
  function publicRequest(r) {
    requireThat(r, "request", "Request not found.", 404);
    const value = {
      id: r.id,
      state: r.state,
      reservedCredits: ["reserved", "submitted", "uncertain"].includes(r.state)
        ? credits(r.reserved)
        : 0,
      chargedCredits: r.state === "settled" ? credits(r.charged) : null,
      provider: r.provider,
      model: r.model,
    };
    if (r.result && r.result_expires > Date.now()) {
      const outcome = decrypt(r.id, r.result);
      if (outcome.error) value.error = outcome.error;
      else value.result = outcome;
    }
    if (r.state === "settled" && r.cost === null && r.charged === 0 && !value.result) {
      value.error = "S2T released this incomplete request. No credits were charged.";
    }
    return value;
  }
  return {
    get(account, id) {
      return publicRequest(ledger.request(account, id));
    },
    cancel(account, id) {
      return publicRequest(ledger.cancel(account, id));
    },
    async run({ account, keyId = null, device = null, idempotencyKey, body, timings = {} }) {
      const started = performance.now();
      requireThat(
        typeof idempotencyKey === "string" && /^[A-Za-z0-9_-]{16,128}$/.test(idempotencyKey),
        "idempotency",
        "Provide a unique Idempotency-Key of 16–128 letters, numbers, underscores or hyphens.",
      );
      const bodyHash = requestBodyHash(body);
      const prior = ledger.replay({account,keyId,dedup:idempotencyKey,bodyHash,legacyFingerprint:legacySpeechFingerprint(body),
        bodyProvider:body?.provider,legacyAudioProvided:typeof body?.audio === 'string'});
      if (prior) return publicRequest(prior);
      const prepared = prepareRequest(body, await resolvePolicy(body));
      const { request, created } = ledger.reserve({
        account,
        keyId,
        device,
        dedup: idempotencyKey,
        bodyHash,
        ...prepared,
        feeBps: prepared.price.feeBps,
      });
      timings.reserve = performance.now() - started;
      if (!created) return publicRequest(request);
      try {
        ledger.submit(request.id);
      } catch (error) {
        ledger.cancel(account, request.id);
        throw error;
      }
      const confirming = performance.now();
      try {
        await confirmReservation();
      } catch (error) {
        ledger.reject(request.id, encrypt(request.id, { error: "The service could not save the reservation. No provider request was sent." }));
        throw error;
      }
      timings.durability = performance.now() - confirming;
      try {
        const executing = performance.now();
        let receipt;
        try { receipt = await execute(prepared); }
        finally { timings.provider = performance.now() - executing; }
        const settling = performance.now();
        const result = encrypt(request.id, receipt.error ? { error: receipt.error } : { text: receipt.text, model: receipt.model, host: receipt.host });
        const settled = ledger.settle(request.id, {
          ...receipt,
          result,
        });
        if (!settled)
          throw new Fault("cost_mismatch", "Provider charge requires reconciliation.", 503);
        timings.settle = performance.now() - settling;
      } catch (error) {
        if (error instanceof ProviderRejected) ledger.reject(request.id, encrypt(request.id, { error: error.message }));
        else ledger.uncertain(
          request.id,
          error instanceof Fault ? error.code : "Provider outcome unknown",
          typeof error?.providerId === "string" ? error.providerId : null,
          { pauseSpending: false },
        );
      }
      return publicRequest(ledger.request(account, request.id));
    },
  };
}
