import { createHash } from "node:crypto";
import { requireThat, integer } from "./money.mjs";
export const fixturePolicy = Object.freeze({
  version: "fixture-v1",
  expires: "2099-01-01T00:00:00Z",
  routes: {
    "openrouter:cleanup": {
      model: "openai/gpt-oss-120b",
      host: "cerebras/fp16",
      inputMicrosPerToken: 1,
      outputMicrosPerToken: 2,
      maxOutputTokens: 512,
      maxInputBytes: 16000,
      maxRequestMicros: 50000,
      feeBps: 550,
    },
    "assemblyai:transcription": {
      model: "universal-3-5-pro",
      microsPerSecond: 125,
      maxSeconds: 120,
      maxRequestMicros: 20000,
      feeBps: 0,
    },
    "elevenlabs:transcription": {
      model: "scribe_v2",
      microsPerSecond: 150,
      maxSeconds: 120,
      maxRequestMicros: 25000,
      feeBps: 0,
    },
  },
});
export function validatePolicy(policy, { live = false, now = Date.now() } = {}) {
  requireThat(
    policy &&
      typeof policy.version === "string" &&
      policy.version.length <= 100 &&
      Date.parse(policy.expires) > now,
    "price_expired",
    "A current pricing policy is required.",
  );
  if (live)
    requireThat(
      Date.parse(policy.expires) <= now + 86400000,
      "price_expiry",
      "Live pricing must be reviewed at least daily.",
    );
  requireThat(
    policy.routes && Object.keys(policy.routes).length > 0,
    "price_routes",
    "No priced operations are enabled.",
  );
  for (const [id, p] of Object.entries(policy.routes)) {
    requireThat(
      ["openrouter:cleanup", "assemblyai:transcription", "elevenlabs:transcription"].includes(id),
      "route",
      "Unsupported provider operation.",
    );
    requireThat(
      typeof p.model === "string" && p.model.length > 0 && p.model.length <= 200,
      "model",
      "Invalid configured model.",
    );
    integer(p.maxRequestMicros, 1, 250000, "Request ceiling");
    integer(p.feeBps, 0, 10000, "Funding fee");
    if (id === "openrouter:cleanup") {
      requireThat(
        p.model === "openai/gpt-oss-120b" && p.host === "cerebras/fp16",
        "model",
        "Only the reviewed Cerebras GPT-OSS route is enabled.",
      );
      integer(p.inputMicrosPerToken, 1, 100, "Input rate");
      integer(p.outputMicrosPerToken, 1, 100, "Output rate");
      integer(p.maxOutputTokens, 1, 2048, "Output limit");
      integer(p.maxInputBytes, 1, 16000, "Input limit");
    } else {
      requireThat(
        p.model === (id.startsWith("assemblyai") ? "universal-3-5-pro" : "scribe_v2"),
        "model",
        "Unsupported speech model.",
      );
      integer(p.microsPerSecond, 1, 10000, "Audio rate");
      integer(p.maxSeconds, 1, 120, "Audio duration");
    }
  }
  return policy;
}
export function parseWave(base64, maxSeconds) {
  requireThat(
    typeof base64 === "string" &&
      base64.length <= 11000000 &&
      /^[A-Za-z0-9+/]+={0,2}$/.test(base64),
    "audio",
    "Provide a base64 PCM WAV file.",
  );
  const audio = Buffer.from(base64, "base64");
  requireThat(
    audio.toString("base64") === base64 &&
      audio.length >= 44 &&
      audio.subarray(0, 4).toString() === "RIFF" &&
      audio.subarray(8, 12).toString() === "WAVE" &&
      audio.readUInt32LE(4) + 8 === audio.length,
    "audio",
    "Invalid WAV container.",
  );
  let offset = 12,
    format = null,
    data = null;
  while (offset < audio.length) {
    requireThat(offset + 8 <= audio.length, "audio", "Truncated WAV chunk.");
    const id = audio.toString("ascii", offset, offset + 4),
      size = audio.readUInt32LE(offset + 4);
    offset += 8;
    requireThat(offset + size <= audio.length, "audio", "Invalid WAV chunk length.");
    if (id === "fmt ") {
      requireThat(!format && size === 16, "audio", "Only canonical PCM WAV is accepted.");
      format = audio.subarray(offset, offset + size);
    } else if (id === "data") {
      requireThat(!data, "audio", "Multiple audio chunks are not supported.");
      data = audio.subarray(offset, offset + size);
    } else requireThat(["JUNK", "LIST"].includes(id), "audio", "Unsupported WAV chunk.");
    offset += size + (size % 2);
  }
  requireThat(offset === audio.length && format && data, "audio", "Incomplete WAV file.");
  const channels = format.readUInt16LE(2),
    rate = format.readUInt32LE(4),
    block = format.readUInt16LE(12);
  requireThat(
    format.readUInt16LE(0) === 1 &&
      channels === 1 &&
      [16000, 24000, 44100, 48000].includes(rate) &&
      format.readUInt16LE(14) === 16 &&
      block === 2 &&
      format.readUInt32LE(8) === rate * block &&
      data.length > 0 &&
      data.length % block === 0,
    "audio",
    "Use mono 16-bit PCM WAV at a supported sample rate.",
  );
  const seconds = data.length / (rate * block);
  requireThat(
    seconds <= maxSeconds,
    "audio_limit",
    "Recording exceeds the configured duration limit.",
  );
  return { audio, seconds };
}
export function prepareRequest(body, policy, now = Date.now()) {
  validatePolicy(policy, { now });
  requireThat(
    body && typeof body === "object" && !Array.isArray(body),
    "request",
    "Invalid request.",
  );
  requireThat(
    Object.keys(body).every((k) => ["provider", "operation", "text", "audio", "model", "instructions"].includes(k)),
    "request",
    "Unexpected request field.",
  );
  const p = policy.routes[`${body.provider}:${body.operation}`];
  requireThat(p, "route", "This provider operation is not enabled.");
  requireThat(!body.model || body.model === p.model, "model", "Model is not allowed.");
  let prepared, maxCost;
  if (body.operation === "cleanup") {
    requireThat(
      typeof body.text === "string" &&
        body.text.trim().length > 0 &&
        Buffer.byteLength(body.text) <= p.maxInputBytes &&
        body.audio === undefined,
      "text",
      "Text is empty or exceeds the configured limit.",
    );
    requireThat(body.instructions === undefined || (typeof body.instructions === "string" && Buffer.byteLength(body.instructions) <= 16000), "instructions", "Editing instructions exceed the limit.");
    maxCost =
      (Buffer.byteLength(body.text) + Buffer.byteLength(body.instructions || "") + 1024) * p.inputMicrosPerToken +
      p.maxOutputTokens * p.outputMicrosPerToken;
    prepared = { text: body.text, instructions: body.instructions };
  } else {
    requireThat(body.text === undefined && body.instructions === undefined, "request", "Unexpected text field.");
    prepared = parseWave(body.audio, p.maxSeconds);
    maxCost = Math.ceil(prepared.seconds) * p.microsPerSecond;
  }
  requireThat(
    maxCost <= p.maxRequestMicros,
    "price_ceiling",
    "Request cannot be priced within the approved ceiling.",
  );
  const fingerprint = createHash("sha256")
    .update(JSON.stringify([body.provider, body.operation, p.model, prepared.text ?? body.audio, prepared.instructions ?? null]))
    .digest("hex");
  return {
    ...prepared,
    provider: body.provider,
    operation: body.operation,
    model: p.model,
    price: p,
    priceVersion: policy.version,
    maxCost,
    fingerprint,
  };
}
