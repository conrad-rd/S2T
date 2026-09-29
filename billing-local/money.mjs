export const MICRO_USD_PER_CREDIT = 5000;
export class Fault extends Error {
  constructor(code, message, status = 409) {
    super(message);
    this.code = code;
    this.status = status;
  }
}
export function requireThat(condition, code, message, status = 400) {
  if (!condition) throw new Fault(code, message, status);
}
export function integer(value, min, max, label) {
  requireThat(
    Number.isSafeInteger(value) && value >= min && value <= max,
    "invalid_amount",
    `${label} is outside its permitted range.`,
  );
  return value;
}
export function dollarsToMicros(value) {
  requireThat(typeof value === "number" || typeof value === "string", "invalid_cost", "Provider returned an invalid cost.");
  const text = String(value);
  const match = text.length <= 128 && /^(0|[1-9]\d*)(?:\.(\d+))?(?:[eE]([+-]?\d{1,3}))?$/.exec(text);
  requireThat(match, "invalid_cost", "Provider returned an invalid cost.");
  const exponent = Number(match[3] || 0);
  requireThat(Math.abs(exponent) <= 400, "invalid_cost", "Provider cost exponent exceeds supported range.");
  const fraction = match[2] || "";
  const coefficient = BigInt(match[1] + fraction);
  const scale = 6 + exponent - fraction.length;
  const divisor = scale < 0 ? 10n ** BigInt(-scale) : 1n;
  const micros = scale >= 0
    ? coefficient * 10n ** BigInt(scale)
    : (coefficient + divisor - 1n) / divisor;
  requireThat(micros <= 1000000000000n, "invalid_cost", "Provider cost exceeds supported range.");
  return Number(micros);
}
export function fundedMicros(cents) {
  return integer(cents, 100, 10000, "Purchase") * MICRO_USD_PER_CREDIT;
}
export function withFee(micros, basisPoints) {
  return Math.ceil((micros * (10000 + basisPoints)) / 10000);
}
export function credits(micros) {
  return micros / MICRO_USD_PER_CREDIT;
}
