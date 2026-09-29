import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createLedger } from '../ledger-core.mjs';
import { fundedMicros, credits } from '../money.mjs';

test('new purchase economics remain positive under conservative VAT, card and funding costs', () => {
  for (const cents of [500, 501, 1000, 2000, 5000, 10000]) {
    const gross = cents / 100;
    const ai = fundedMicros(cents) / 1e6;
    assert.equal(ai, gross * .5);
    assert.equal(credits(fundedMicros(cents)), cents);
    for (const vat of [.19, .27]) for (const providerFee of [.055, .16]) {
      const contribution = gross / (1 + vat) - ai * (1 + providerFee) - gross * .055 - .35;
      assert.ok(contribution > 0, `${cents} cents, VAT ${vat}, provider fee ${providerFee}`);
    }
  }
});

test('new checkouts require $5 and retain their funding rate through retries', () => {
  const db=new DatabaseSync(':memory:'); const ledger=createLedger(db);
  const {account}=ledger.createSession();
  for (const cents of [100,200,300,499]) assert.throws(()=>ledger.checkoutOrder(account,cents,'small-checkout-'+cents),/Top-up/);
  const order=ledger.checkoutOrder(account,500,'new-checkout-fixture');
  assert.equal(order.funding_rate,5000);
  ledger.attachCheckout(order.id,'cs_new');
  ledger.grant({account,cents:500,session:'cs_new',intent:'pi_new'});
  assert.equal(ledger.summary(account).balance,500);
  assert.equal(ledger.grant({account,cents:500,session:'cs_new',intent:'pi_new'}),false);
  db.close();
});

test('pre-existing $1 checkout retains its original $0.80 provider value after migration', () => {
  const db=new DatabaseSync(':memory:');
  db.exec('CREATE TABLE checkout_orders(id TEXT PRIMARY KEY,account TEXT NOT NULL,dedup TEXT NOT NULL,cents INTEGER NOT NULL,created INTEGER NOT NULL,session TEXT UNIQUE,url TEXT,UNIQUE(account,dedup));');
  const ledger=createLedger(db);const {account}=ledger.createSession();
  db.prepare('INSERT INTO checkout_orders(id,account,dedup,cents,created,session,url) VALUES(?,?,?,?,?,?,?)').run('old-order',account,'old-checkout-fixture',100,Date.now(),'cs_old','https://checkout.stripe.com/c/pay/old');
  const old=ledger.checkoutOrder(account,100,'old-checkout-fixture');
  assert.equal(old.funding_rate,8000);
  ledger.verifyCheckout(old.id,account,100,'cs_old');
  ledger.grant({account,cents:100,session:'cs_old',intent:'pi_old'});
  assert.equal(ledger.summary(account).balance,160);
  ledger.reverse({id:'refund-old',intent:'pi_old',cents:50,kind:'refund'});
  assert.equal(ledger.summary(account).balance,80);
  assert.throws(()=>ledger.grant({account:ledger.createSession().account,cents:100,session:'cs_old',intent:'wrong-account'}));
  db.close();
});

test('migration distinguishes original 90% quotes from later 80% quotes without rewriting amounts', () => {
  const db=new DatabaseSync(':memory:');
  db.exec('CREATE TABLE checkout_orders(id TEXT PRIMARY KEY,account TEXT NOT NULL,dedup TEXT NOT NULL,cents INTEGER NOT NULL,created INTEGER NOT NULL,session TEXT UNIQUE,url TEXT,UNIQUE(account,dedup));');
  const cutoff=Date.parse('2026-09-19T13:22:28.870Z');
  const insert=db.prepare('INSERT INTO checkout_orders VALUES(?,?,?,?,?,?,?)');
  insert.run('old','fixture','old-checkout',100,cutoff-1,'cs_old',null);
  insert.run('recent','fixture','recent-checkout',100,cutoff,'cs_recent',null);
  createLedger(db);
  const rows=db.prepare('SELECT id,cents,funding_rate FROM checkout_orders ORDER BY created').all();
  assert.deepEqual(rows.map(r=>[r.id,r.cents,r.funding_rate]),[['old',100,9000],['recent',100,8000]]);
  createLedger(db);
  assert.deepEqual(db.prepare('SELECT id,cents,funding_rate FROM checkout_orders ORDER BY created').all(),rows);
  db.close();
});

test('unpaid checkout quotes cannot fund another account or a different amount', () => {
  const db=new DatabaseSync(':memory:');const ledger=createLedger(db);
  const a=ledger.createSession().account,b=ledger.createSession().account;
  const order=ledger.checkoutOrder(a,500,'bound-price-fixture');ledger.attachCheckout(order.id,'cs_bound');
  assert.throws(()=>ledger.grant({account:b,cents:500,session:'cs_bound',intent:'pi_wrong_owner'}),/does not match/);
  assert.throws(()=>ledger.grant({account:a,cents:600,session:'cs_bound',intent:'pi_wrong_amount'}),/does not match/);
  assert.equal(ledger.summary(a).balance,0);assert.equal(ledger.summary(b).balance,0);
  ledger.grant({account:a,cents:500,session:'cs_bound',intent:'pi_bound'});
  ledger.reverse({id:'refund_bound',intent:'pi_bound',cents:500,kind:'refund'});
  assert.equal(ledger.summary(a).balance,0);
  db.close();
});

test('interrupted quote migration rolls back the column so retry preserves the original price', () => {
  const db = new DatabaseSync(':memory:');
  db.exec('CREATE TABLE checkout_orders(id TEXT PRIMARY KEY,account TEXT NOT NULL,dedup TEXT NOT NULL,cents INTEGER NOT NULL,created INTEGER NOT NULL,session TEXT UNIQUE,url TEXT,UNIQUE(account,dedup));');
  db.prepare('INSERT INTO checkout_orders VALUES(?,?,?,?,?,?,?)').run('old','fixture','old-checkout',100,0,'cs_old',null);
  const interrupted = {
    exec: sql => db.exec(sql),
    prepare(sql) {
      if (sql.startsWith('UPDATE checkout_orders SET funding_rate=9000')) throw new Error('simulated storage interruption');
      return db.prepare(sql);
    },
  };
  assert.throws(() => createLedger(interrupted), /storage interruption/);
  assert.equal(db.prepare('PRAGMA table_info(checkout_orders)').all().some(c => c.name === 'funding_rate'), false);
  createLedger(db);
  assert.equal(db.prepare('SELECT funding_rate FROM checkout_orders').get().funding_rate, 9000);
  db.close();
});
