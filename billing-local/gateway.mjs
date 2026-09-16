import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";
import { prepareRequest } from "./policy.mjs";
import { requireThat, Fault, credits } from "./money.mjs";
export function createGateway({ ledger, policy, execute, encryptionKey, confirmReservation = async () => {} }) {
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
    if (r.result && r.result_expires > Date.now()) value.result = decrypt(r.id, r.result);
    return value;
  }
  return {
    get(account, id) {
      return publicRequest(ledger.request(account, id));
    },
    cancel(account, id) {
      return publicRequest(ledger.cancel(account, id));
    },
    async run({ account, keyId = null, idempotencyKey, body }) {
      requireThat(
        typeof idempotencyKey === "string" && /^[A-Za-z0-9_-]{16,128}$/.test(idempotencyKey),
        "idempotency",
        "Provide a unique Idempotency-Key of 16–128 letters, numbers, underscores or hyphens.",
      );
      const prepared = prepareRequest(body, policy);
      const { request, created } = ledger.reserve({
        account,
        keyId,
        dedup: idempotencyKey,
        ...prepared,
        feeBps: prepared.price.feeBps,
      });
      if (!created) return publicRequest(request);
      try {
        ledger.submit(request.id);
      } catch (error) {
        ledger.cancel(account, request.id);
        throw error;
      }
      try {
        await confirmReservation();
        const receipt = await execute(prepared);
        const result = encrypt(request.id, { text: receipt.text, model: receipt.model, host: receipt.host });
        const settled = ledger.settle(request.id, {
          ...receipt,
          result,
        });
        if (!settled)
          throw new Fault("cost_mismatch", "Provider charge requires reconciliation.", 503);
      } catch (error) {
        ledger.uncertain(
          request.id,
          error instanceof Fault ? error.code : "Provider outcome unknown",
        );
      }
      return publicRequest(ledger.request(account, request.id));
    },
  };
}
