import { credits, requireThat } from './money.mjs';

const DAY = 86400000;
export function usageSummary(db, account, days, now) {
  requireThat([7, 30, 90].includes(days), 'period', 'Choose 7, 30 or 90 days.');
  const from = Math.floor(now / DAY) * DAY - (days - 1) * DAY;
  const rows = db.prepare("SELECT CAST(created / 86400000 AS INTEGER) * 86400000 AS day, SUM(-amount) AS charged, SUM(CASE WHEN kind='usage' THEN 1 ELSE 0 END) AS requests FROM ledger WHERE account=? AND kind IN ('usage','usage_correction') AND created>=? AND created<=? GROUP BY day ORDER BY day").all(account, from, now);
  const byDay = new Map(rows.map(row => [row.day, row]));
  const series = Array.from({ length: days }, (_, index) => {
    const timestamp = from + index * DAY, row = byDay.get(timestamp);
    return { day: new Date(timestamp).toISOString().slice(0, 10), credits: credits(row?.charged ?? 0), requests: row?.requests ?? 0 };
  });
  const providers = db.prepare("SELECT r.provider, SUM(-l.amount) AS charged FROM ledger l JOIN requests r ON (l.reference='usage:' || r.id OR l.reference='usage-correction:' || r.id) AND r.account=l.account WHERE l.account=? AND l.kind IN ('usage','usage_correction') AND l.created>=? AND l.created<=? GROUP BY r.provider ORDER BY charged DESC").all(account, from, now).map(row => ({ provider: row.provider, credits: credits(row.charged) }));
  const last = db.prepare("SELECT l.created, d.name, d.device_id FROM ledger l LEFT JOIN requests r ON l.reference='usage:' || r.id AND r.account=l.account LEFT JOIN request_devices d ON d.request_id=r.id WHERE l.account=? AND l.kind='usage' AND l.created<=? ORDER BY l.created DESC,l.rowid DESC LIMIT 1").get(account, now);
  return {
    days, from, through: now, timezone: 'UTC', series, providers,
    spentCredits: credits(rows.reduce((sum, row) => sum + row.charged, 0)),
    requestCount: rows.reduce((sum, row) => sum + row.requests, 0),
    lastUsed: last ? { at: last.created, device: last.device_id ? { name: last.name, suffix: last.device_id.slice(-4).toUpperCase() } : null } : null,
  };
}

export function requestDevice(id, name) {
  if (!id && !name) return null;
  requireThat(typeof id === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id), 'device', 'Invalid device identifier.');
  requireThat(['Mac', 'MacBook Air', 'MacBook Pro', 'Mac mini', 'Mac Studio', 'Mac Pro', 'iMac'].includes(name), 'device', 'Invalid device label.');
  return { id: id.toLowerCase(), name };
}
