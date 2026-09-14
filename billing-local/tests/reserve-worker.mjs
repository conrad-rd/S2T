import { workerData, parentPort } from "node:worker_threads";
import { openLedger } from "../ledger.mjs";
const l = openLedger(workerData.path, { limits: workerData.limits });
try {
  l.reserve({
    account: workerData.account,
    dedup: `request_${workerData.index}`,
    fingerprint: `request_${workerData.index}`,
    provider: "openrouter",
    model: "fixture",
    priceVersion: "v1",
    maxCost: 200000,
  });
  parentPort.postMessage(true);
} catch {
  parentPort.postMessage(false);
} finally {
  l.close();
}
