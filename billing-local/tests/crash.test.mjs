import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import { openLedger } from "../ledger.mjs";
test("SIGKILL at reservation, submission and settlement preserves the right balance", async () => {
  for (const stage of ["reserved", "submitted", "settled"]) {
    const path = mkdtempSync(tmpdir() + "/s2t-crash-") + "/ledger.sqlite";
    const processChild = spawn(
      process.execPath,
      [fileURLToPath(new URL("./crash-worker.mjs", import.meta.url)), path, stage],
      { stdio: ["ignore", "pipe", "pipe"] },
    );
    let info;
    try {
      const [line] = await once(processChild.stdout, "data");
      info = JSON.parse(line.toString());
    } finally {
      processChild.kill("SIGKILL");
      await once(processChild, "exit");
    }
    const l = openLedger(path);
    l.claim();
    l.recover();
    const r = l.request(info.account, info.id),
      summary = l.summary(info.account);
    assert.equal(
      r.state,
      stage === "reserved" ? "released" : stage === "submitted" ? "uncertain" : "settled",
    );
    assert.equal(summary.balance, stage === "settled" ? 99.99 : 100);
    assert.equal(summary.reserved, stage === "submitted" ? 1000 / 9000 : 0);
    assert.equal(summary.paused, stage === "submitted");
    l.unclaim();
    l.close();
  }
});
