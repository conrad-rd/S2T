import { configuration } from "./config.mjs";
import { openLedger, hash } from "./ledger.mjs";
import { readFileSync } from "node:fs";
const config = configuration(),
  ledger = openLedger(config.dataDir + `/${config.mode}-ledger.sqlite`, { mode: config.mode });
try {
  const [action = "status", file] = process.argv.slice(2);
  if (action === "pause") ledger.pause("Operator emergency stop");
  else if (action === "resume") ledger.resume();
  else if (action === "review-pricing") ledger.reviewPricing(config.policy.version);
  else if (action === "reconcile") {
    if (!file) throw Error("Pass a provider evidence JSON file.");
    const raw = readFileSync(file, "utf8"),
      report = JSON.parse(raw);
    if (!Array.isArray(report.receipts) || !report.source || !report.generatedAt)
      throw Error("Report requires source, generatedAt, and receipts.");
    for (const receipt of report.receipts) {
      if (
        !ledger.reconcile(receipt.requestId, {
          cost: receipt.costMicros,
          providerId: receipt.providerId,
          evidence: hash(raw),
        })
      )
        throw Error("Provider mismatch. Service remains paused.");
    }
    if (!Array.isArray(report.totals) || !report.totals.length)
      throw Error("A full report must include provider account totals.");
    for (const total of report.totals) {
      if (!ledger.reconcileReport({ ...total, evidence: hash(raw) }))
        throw Error("Unexplained provider spending. Service remains paused.");
    }
  } else if (action !== "status")
    throw Error("Use status, pause, resume, review-pricing, or reconcile <provider-report.json>.");
  console.log(JSON.stringify(ledger.health(), null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  ledger.close();
}
