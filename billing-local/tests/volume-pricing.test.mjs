import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createLedger } from '../ledger-core.mjs';
import { quoteCredits } from '../public/credit-pricing.js';

test('approved tiers and every custom cent keep credit amounts and value monotone', () => {
  for (const [cents, credits] of [[500,500],[1000,1100],[2000,2300],[5000,5800],[10000,11800]]) {
    assert.equal(quoteCredits(cents).credits, credits);
  }
  let previous = quoteCredits(500);
  for (let cents=501;cents<=10000;cents++) {
    const q=quoteCredits(cents);
    assert.ok(Number.isSafeInteger(q.grantMicros));
    assert.ok(q.grantMicros>previous.grantMicros);
    assert.ok(q.grantMicros*(cents-1)>=previous.grantMicros*cents);
    assert.ok(cents/100/1.27-q.grantMicros/1e6*1.10-cents/100*.0765-.30>0);
    previous=q;
  }
  for (const value of [0,499,10001,501.2,NaN,'500']) assert.throws(()=>quoteCredits(value));
});

test('custom-price refunds use the original grant and cumulative exact rounding', () => {
  const db=new DatabaseSync(':memory:');const ledger=createLedger(db);
  const {account}=ledger.createSession();
  const order=ledger.checkoutOrder(account,2001,'custom-purchase-test');
  assert.equal(order.grant_micros,11505833);
  ledger.attachCheckout(order.id,'cs_volume');
  ledger.grant({account,cents:2001,session:'cs_volume',intent:'pi_volume'});
  assert.equal(ledger.checkoutOrder(account,2001,'custom-purchase-test').grant_micros,order.grant_micros);
  const original=ledger.summary(account).purchases[0];
  assert.equal(original.grantedCredits,2301.1666);
  for (let i=1;i<=7;i++) {
    ledger.reverse({id:`re_${i}`,intent:'pi_volume',cents:1,kind:'refund'});
    assert.equal(ledger.summary(account).balance,(11505833-Math.floor(11505833*i/2001))/5000);
  }
  ledger.reverse({id:'re_rest',intent:'pi_volume',cents:1994,kind:'refund'});
  assert.equal(ledger.summary(account).balance,0);
  assert.equal(ledger.summary(account).purchases[0].netCredits,0);
  assert.equal(ledger.funding().providerMicros,0);
  assert.equal(db.prepare("SELECT SUM(amount) n FROM ledger WHERE account=?").get(account).n,0);
  db.close();
});

test('existing quoted grants survive migration and won disputes restore exact custom grants', () => {
  const db=new DatabaseSync(':memory:');
  db.exec('CREATE TABLE checkout_orders(id TEXT PRIMARY KEY,account TEXT NOT NULL,dedup TEXT NOT NULL,cents INTEGER NOT NULL,created INTEGER NOT NULL,session TEXT UNIQUE,url TEXT,funding_rate INTEGER NOT NULL,UNIQUE(account,dedup));');
  db.prepare('INSERT INTO checkout_orders VALUES(?,?,?,?,?,?,?,?)').run('legacy','old','old-checkout',2000,1,'cs_old',null,5000);
  const ledger=createLedger(db);
  assert.equal(db.prepare('SELECT grant_micros FROM checkout_orders').get().grant_micros,10000000);
  const {account}=ledger.createSession();
  const order=ledger.checkoutOrder(account,2001,'volume-dispute-test');ledger.attachCheckout(order.id,'cs_new');
  ledger.grant({account,cents:2001,session:'cs_new',intent:'pi_new'});
  ledger.dispute({id:'dp_volume',intent:'pi_new',cents:1,status:'needs_response'});
  ledger.dispute({id:'dp_volume',intent:'pi_new',cents:1,status:'won'});
  assert.equal(ledger.summary(account).balance,2301.1666);
  assert.equal(ledger.summary(ledger.createSession().account).purchases.length,0);
  db.close();
});
