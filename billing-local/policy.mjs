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
  },
});
export function validatePolicy(policy, { live = false, now = Date.now() } = {}) {
  requireThat(
    policy &&
      typeof policy.version === "string" &&
      policy.version.length <= 100 &&
      (policy.expires === null || Date.parse(policy.expires) > now),
    "price_expired",
    "A current pricing policy is required.",
  );
  if (live)
    requireThat(
      policy.version !== "fixture-v1",
      "price_expiry",
      "Live mode requires a production pricing policy.",
    );
  requireThat(
    policy.routes && Object.keys(policy.routes).length > 0,
    "price_routes",
    "No priced operations are enabled.",
  );
  for (const [id, route] of Object.entries(policy.routes)) {
    requireThat(!route.alternatives || (Array.isArray(route.alternatives) && route.alternatives.length <= 51), "models", "Too many configured models.");
    const variants = [route, ...(route.alternatives || [])];
    requireThat(new Set(variants.map(p => `${p.model}:${p.host || ""}`)).size === variants.length, "models", "Duplicate model and host.");
    for (const p of variants) {
      requireThat(
        ["openrouter:decisions", "openrouter:cleanup", "assemblyai:transcription", "openrouter:transcription", "xai:cleanup", "xai:transcription"].includes(id),
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
      if (id === "openrouter:decisions") {
        requireThat(p.model === "typesafe/jev-1.13" && !p.host, "model", "Unsupported Jev model.");
        integer(p.inputMicrosPerThousandTokens, 42, 42, "Jev input rate");
        integer(p.maxInputBytes, 1, 65536, "Jev input limit");
      } else if (id === "xai:cleanup") {
        requireThat(/^grok-[A-Za-z0-9_.-]{1,190}$/.test(p.model) && !p.host, "model", "Unsupported xAI cleanup model or host.");
        integer(p.inputMicrosPerToken, 1, 100, "Input ceiling");
        integer(p.outputMicrosPerToken, 1, 100, "Output ceiling");
        integer(p.maxOutputTokens, 1, 2048, "Output limit");
        integer(p.maxInputBytes, 1, 16000, "Input limit");
      } else if (id === "openrouter:cleanup") {
        requireThat(
          /^[a-zA-Z0-9._-]+\/[a-zA-Z0-9._:/-]+$/.test(p.model) && p.model !== "cerebras/fp16" &&
            (p.host === undefined || (typeof p.host === "string" && /^[a-zA-Z0-9._/-]{1,100}$/.test(p.host))),
          "model",
          "Configure a valid model and optional hosting endpoint.",
        );
        requireThat(p.requiresDataCollection === undefined || (p.requiresDataCollection === true && p.model === "meta/muse-spark-1.3-contributor"), "privacy", "Data collection requires an explicitly supported contributor model.");
        requireThat(p.model !== "meta/muse-spark-1.3-contributor" || p.requiresDataCollection === true, "privacy", "Contributor models require explicit consent.");
        integer(p.inputMicrosPerToken, 1, p.catalogPriced ? 1250000 : 100, "Input rate");
        integer(p.outputMicrosPerToken, 1, p.catalogPriced ? 1250000 : 100, "Output rate");
        integer(p.maxOutputTokens, 1, p.catalogPriced ? 8192 : 2048, "Output limit");
        integer(p.maxInputBytes, 1, 16000, "Input limit");
        if (p.catalogPriced) integer(p.requestMicros, 0, 1250000, "Request rate");
      } else {
        requireThat(
          id === "xai:transcription" ? ["grok-voice-transcribe-1.0", "grok-voice-transcribe-2.0"].includes(p.model) : id === "assemblyai:transcription" ? p.model === "universal-3-5-pro" : /^[A-Za-z0-9_~.-]+\/[A-Za-z0-9_~.:-]+$/.test(p.model),
          "model",
          "Unsupported speech model.",
        );
        requireThat(p.reserveRequestCeiling === undefined || (id === "openrouter:transcription" && p.reserveRequestCeiling === true), "price", "Invalid speech reservation mode.");
        if (!p.reserveRequestCeiling) integer(p.microsPerSecond, 1, 10000, "Audio rate");
        if (id === "xai:transcription") integer(p.microsPerHour, 1, p.microsPerSecond * 3600, "Hourly audio rate");
        integer(p.maxSeconds, 1, 120, "Audio duration");
        if (p.minimumBillableSeconds !== undefined) {
          requireThat(id === "openrouter:transcription" && !p.reserveRequestCeiling, "price", "A duration minimum requires duration-priced OpenRouter speech.");
          integer(p.minimumBillableSeconds, 1, p.maxSeconds, "Minimum billed duration");
        }
      }
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
    Object.keys(body).every((k) => ["provider", "operation", "text", "audio", "model", "instructions", "host", "reasoning", "fast", "allowDataCollection"].includes(k)),
    "request",
    "Unexpected request field.",
  );
  const route = policy.routes[`${body.provider}:${body.operation}`];
  requireThat(route, "route", "This provider operation is not enabled.");
  let p = [route, ...(route.alternatives || [])].find(p => (!body.model || body.model === p.model) && (body.host === undefined || body.host === (p.host || "")));
  requireThat(p, "model", "This model and host are not available with S2T. Refresh your key to load available models.");
  requireThat(body.reasoning === undefined || ["", "none", "minimal", "low", "medium", "high", "xhigh", "max"].includes(body.reasoning), "reasoning", "Unsupported reasoning effort.");
  requireThat(body.fast === undefined || ["true", "false"].includes(body.fast), "fast", "Invalid speed setting.");
  requireThat(body.operation === "cleanup" || (body.host === undefined && body.reasoning === undefined && body.fast === undefined), "request", "Unexpected cleanup setting.");
  requireThat(body.allowDataCollection === undefined || ["true", "false"].includes(body.allowDataCollection), "privacy", "Invalid data-use permission.");
  requireThat(!p.requiresDataCollection || body.allowDataCollection === "true", "privacy", "Muse Spark Contributor requires your opt-in under Models. Meta may use prompts and responses to improve its products.");
  requireThat(body.allowDataCollection !== "true" || p.requiresDataCollection === true, "privacy", "Data-use permission applies only to Contributor.");
  let prepared, maxCost;
  if (body.operation === "decisions") {
    requireThat(typeof body.text === "string" && Buffer.byteLength(body.text) <= p.maxInputBytes && body.audio === undefined && body.instructions === undefined, "decisions", "Invalid Jev request.");
    let decision;
    try { decision = JSON.parse(body.text); } catch { requireThat(false, "decisions", "Invalid Jev JSON."); }
    requireThat(decision && decision.model === p.model && decision.state && typeof decision.state === "object" && !Array.isArray(decision.state) && decision.questions && typeof decision.questions === "object" && !Array.isArray(decision.questions) && Object.keys(decision).every(k => ["model", "state", "questions"].includes(k)), "decisions", "Invalid Jev request fields.");
    const questions = Object.entries(decision.questions);
    requireThat(questions.length > 0 && questions.length <= 49 && questions.every(([id,q]) => /^(edit[0-9]{1,2}|simple)$/.test(id) && q && q.type === "noul" && typeof q.instructions === "string" && q.instructions.length <= 4096 && Object.keys(q).every(k => ["type", "instructions", "criteria"].includes(k))), "decisions", "Invalid Jev questions.");
    maxCost = Math.ceil((Buffer.byteLength(body.text) + 1024) * p.inputMicrosPerThousandTokens / 1000);
    prepared = { text: body.text, decision };
  } else if (body.operation === "cleanup") {
    requireThat(
      typeof body.text === "string" &&
        body.text.trim().length > 0 &&
        Buffer.byteLength(body.text) <= p.maxInputBytes &&
        body.audio === undefined,
      "text",
      "Text is empty or exceeds the configured limit.",
    );
    requireThat(body.instructions === undefined || (typeof body.instructions === "string" && Buffer.byteLength(body.instructions) <= 16000), "instructions", "Editing instructions exceed the limit.");
    if (p.catalogPriced) {
      const inputCost = (Buffer.byteLength(body.text) + Buffer.byteLength(body.instructions || "") + 1024) * p.inputMicrosPerToken + p.requestMicros;
      const outputLimit = Math.min(p.maxOutputTokens, Math.floor((p.maxRequestMicros - inputCost) / p.outputMicrosPerToken));
      requireThat(outputLimit >= 512, "price_ceiling", "This model cannot process this transcript within the S2T request budget. Use a shorter transcript or a less expensive model.");
      p = {...p,maxOutputTokens:outputLimit};
    }
    maxCost = (p.requestMicros || 0) +
      (Buffer.byteLength(body.text) + Buffer.byteLength(body.instructions || "") + 1024) * p.inputMicrosPerToken +
      p.maxOutputTokens * p.outputMicrosPerToken;
    prepared = { text: body.text, instructions: body.instructions, reasoning: body.reasoning || undefined, fast: body.fast === "true", allowDataCollection: p.requiresDataCollection === true && body.allowDataCollection === "true" };
  } else {
    requireThat(body.text === undefined && body.instructions === undefined, "request", "Unexpected text field.");
    prepared = parseWave(body.audio, p.maxSeconds);
    maxCost = p.reserveRequestCeiling ? p.maxRequestMicros : Math.max(Math.ceil(prepared.seconds), p.minimumBillableSeconds ?? 1) * p.microsPerSecond;
  }
  requireThat(
    maxCost <= p.maxRequestMicros,
    "price_ceiling",
    "Request cannot be priced within the approved ceiling.",
  );
  const identity = [body.provider, body.operation, p.model, prepared.text ?? body.audio, prepared.instructions ?? null];
  if (body.host !== undefined || body.reasoning !== undefined || body.fast !== undefined || body.allowDataCollection !== undefined) {
    identity.push(p.host ?? null, prepared.reasoning ?? null, prepared.fast ?? false, prepared.allowDataCollection ?? false);
  }
  const fingerprint = createHash("sha256")
    .update(JSON.stringify(identity))
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

export function modelCatalog(policy) {
  validatePolicy(policy);
  return Object.entries(policy.routes).flatMap(([id, route]) => {
    const [provider, operation] = id.split(":");
    return [route, ...(route.alternatives || [])].map(p => ({
      provider, operation, model: p.model, host: p.host || "",
      requiresDataCollection: p.requiresDataCollection === true,
      title: p.title || (p.model === "openai/gpt-oss-120b" ? "GPT-OSS 120B" : p.model === "universal-3-5-pro" ? "Universal 3.5 Pro" : p.model),
      ...(p.maxSeconds ? { maxSeconds: p.maxSeconds } : {})
    }));
  });
}
