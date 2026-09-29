export const CREDIT_PRICE_VERSION = 'volume-2026-09-19';
export const CREDIT_TIERS = Object.freeze([[500,500],[1000,1100],[2000,2300],[5000,5800],[10000,11800]].map(Object.freeze));

export function quoteCredits(cents) {
  if (!Number.isSafeInteger(cents) || cents < 500 || cents > 10000) throw new Error('Choose $5 to $100.');
  const high = CREDIT_TIERS.findIndex(([price]) => price >= cents);
  const [upperPrice, upperCredits] = CREDIT_TIERS[high];
  const [lowerPrice, lowerCredits] = CREDIT_TIERS[Math.max(0, high - 1)];
  const grantMicros = high === 0 ? lowerCredits * 5000 : lowerCredits * 5000 +
    Math.floor((cents - lowerPrice) * (upperCredits - lowerCredits) * 5000 / (upperPrice - lowerPrice));
  return { cents, credits: grantMicros / 5000, grantMicros, version: CREDIT_PRICE_VERSION };
}
