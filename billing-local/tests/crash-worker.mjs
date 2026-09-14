import { openLedger } from "../ledger.mjs";
const [path, stage] = process.argv.slice(2),
  l = openLedger(path);
l.claim();
const { account } = l.createSession();
l.grant({ account, cents: 100, session: "cs", intent: "pi" });
const { request } = l.reserve({
  account,
  dedup: "crash-request-00001",
  fingerprint: "fixture",
  provider: "openrouter",
  model: "fixture",
  priceVersion: "v1",
  maxCost: 1000,
});
if (stage !== "reserved") l.submit(request.id);
if (stage === "settled") l.settle(request.id, { cost: 90, providerId: "receipt" });
console.log(JSON.stringify({ account, id: request.id }));
setInterval(() => {}, 1000);
