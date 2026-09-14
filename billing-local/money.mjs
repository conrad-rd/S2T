export const MICRO_USD_PER_CREDIT = 9000;
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
  const text = String(value);
  requireThat(
    /^(0|[1-9]\d*)(\.\d{1,12})?$/.test(text),
    "invalid_cost",
    "Provider returned an invalid cost.",
  );
  const [whole, fraction = ""] = text.split(".");
  const micros =
    BigInt(whole) * 1000000n +
    BigInt((fraction + "000000").slice(0, 6)) +
    (/[^0]/.test(fraction.slice(6)) ? 1n : 0n);
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
