import { DatabaseSync } from "node:sqlite";
import { createLedger } from "./ledger-core.mjs";
import { requireThat } from "./money.mjs";
export { hash, defaults } from "./ledger-core.mjs";
export function openLedger(path, options = {}) {
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=10000;");
  const ledger = createLedger(db, options);
  db.claim = () => {
    db.exec("BEGIN IMMEDIATE");
    try {
      const owner = db.prepare("SELECT value FROM metadata WHERE key='owner'").get();
      if (owner && Number(owner.value) > 0) {
        let alive = true;
        try { process.kill(Number(owner.value), 0); } catch (error) { if (error.code === "ESRCH") alive = false; }
        requireThat(!alive, "owner", "Another billing server owns this database.");
      }
      db.prepare("INSERT INTO metadata VALUES('owner',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(String(process.pid));
      db.exec("COMMIT");
    } catch (error) { db.exec("ROLLBACK"); throw error; }
  };
  db.unclaim = () => db.prepare("UPDATE metadata SET value='0' WHERE key='owner' AND value=?").run(String(process.pid));
  return ledger;
}
