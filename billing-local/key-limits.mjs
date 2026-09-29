import {requireThat, integer, credits, MICRO_USD_PER_CREDIT} from './money.mjs';
const day = 86400000;
export function createKeyLimits(db, now) {
  db.exec(`CREATE TABLE IF NOT EXISTS api_key_limits(key_id TEXT PRIMARY KEY REFERENCES api_keys(id),cap INTEGER,reset_days INTEGER,anchor INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS requests_key_state ON requests(key_id,state);`);
  const one = (sql, ...args) => db.prepare(sql).get(...args);
  function owned(account, id) {
    const key = one('SELECT id,expires,revoked FROM api_keys WHERE account=? AND id=?', account, id);
    requireThat(key, 'key', 'Key not found.', 404);
    return key;
  }
  function read(account, id) {
    const key = owned(account,id);
    const policy = one('SELECT * FROM api_key_limits WHERE key_id=?',id);
    const period = policy?.reset_days ? policy.reset_days * day : null;
    const start = period ? policy.anchor + Math.max(0,Math.floor((now()-policy.anchor)/period))*period : 0;
    const used = one(`SELECT COALESCE(SUM(-l.amount),0) AS n FROM ledger l JOIN requests r ON (l.reference='usage:' || r.id OR l.reference='usage-correction:' || r.id) WHERE r.key_id=? AND l.kind IN ('usage','usage_correction') AND l.created>=?`,id,start).n;
    const pending = one("SELECT COALESCE(SUM(reserved),0) AS n FROM requests WHERE key_id=? AND state IN ('reserved','submitted','uncertain')",id).n + one("SELECT COALESCE(SUM(authorized-charged),0) n FROM direct_authorizations WHERE key_id=? AND status!='closed'",id).n;
    return {limitCredits: policy?.cap == null ? null : credits(policy.cap), usedCredits:credits(used), reservedCredits:credits(pending),
      remainingCredits:policy?.cap == null ? null : credits(Math.max(0,policy.cap-used-pending)), resetDays:policy?.reset_days ?? null,
      resetsAt:period ? start+period : null, expiresAt:key.expires === Number.MAX_SAFE_INTEGER ? null : key.expires,
      active:!key.revoked && key.expires>now()};
  }
  function configure(account,id,value) {
    requireThat(value && typeof value==='object' && !Array.isArray(value) && Object.keys(value).every(k=>['limitCredits','resetDays','expiresAt'].includes(k)), 'key_policy', 'Invalid key limit settings.');
    const key=owned(account,id);
    requireThat(!key.revoked && key.expires>now(),'key_inactive','This key is revoked or permanently expired. Create a new key.',409);
    const previous=one('SELECT * FROM api_key_limits WHERE key_id=?',id);
    let cap=previous?.cap ?? null, reset=previous?.reset_days ?? null;
    if(value.limitCredits!==undefined){
      if(value.limitCredits===null) cap=null;
      else {
        const amount=value.limitCredits;
        requireThat(typeof amount==='number' && Number.isFinite(amount) && amount>=0 && amount<=1000000 && Math.abs(amount*100-Math.round(amount*100))<0.000001,'key_limit','Use a credit limit from 0 to 1,000,000 with at most two decimal places.');
        cap=Math.round(amount*100)*(MICRO_USD_PER_CREDIT/100);
      }
    }
    if(value.resetDays!==undefined) reset=value.resetDays===null ? null : integer(value.resetDays,1,3650,'Reset interval in days');
    if(value.limitCredits===null && value.resetDays===undefined) reset=null;
    requireThat(reset===null || cap!==null,'key_limit','Set a credit limit before choosing a reset interval.');
    if(cap===null) reset=null;
    if(value.expiresAt!==undefined){
      const expiry=value.expiresAt===null ? Number.MAX_SAFE_INTEGER : integer(value.expiresAt,now()+1,now()+3650*day,'Expiry');
      db.prepare('UPDATE api_keys SET expires=? WHERE id=? AND account=?').run(expiry,id,account);
    }
    db.prepare('INSERT INTO api_key_limits(key_id,cap,reset_days,anchor) VALUES(?,?,?,?) ON CONFLICT(key_id) DO UPDATE SET cap=excluded.cap,reset_days=excluded.reset_days').run(id,cap,reset,Math.floor(now()/day)*day);
    return read(account,id);
  }
  function check(account,id,additional=0) {
    const key=owned(account,id);
    requireThat(!key.revoked && key.expires>now(),'key','API key is revoked or expired.',401);
    const policy=one('SELECT cap FROM api_key_limits WHERE key_id=?',id);
    if(policy?.cap == null) return;
    const status=read(account,id);
    const used=Math.round((status.usedCredits+status.reservedCredits)*MICRO_USD_PER_CREDIT);
    requireThat(used+additional<=policy.cap,'key_limit',status.resetsAt ? `API key credit limit reached. Resets ${new Date(status.resetsAt).toISOString()}. Manage limits in your S2T account.` : 'API key lifetime credit limit reached. Manage limits in your S2T account.',402);
  }
  return {read,configure,check};
}
