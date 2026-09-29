import test from 'node:test';
import assert from 'node:assert/strict';
import {openLedger} from '../ledger.mjs';
const day=86400000;
function setup(){
 let time=Date.UTC(2026,8,18,12);
 const ledger=openLedger(':memory:',{now:()=>time});
 const {account}=ledger.createSession();
 ledger.grant({account,cents:100,session:'fixture',intent:'fixture'});
 const key=ledger.issueKey(account);
 let sequence=0;
 const reserve=(cost=2500, keyId=key.id)=>ledger.reserve({account,keyId,dedup:'request-'+ ++sequence,fingerprint:'fixture',provider:'openrouter',model:'fixture/model',priceVersion:'fixture',maxCost:cost}).request;
 const settle=r=>{ledger.submit(r.id);ledger.settle(r.id,{cost:r.reserved,providerId:'receipt-'+r.id,result:'encrypted fixture'});};
 return {ledger,account,key,reserve,settle,advance:ms=>time+=ms,now:()=>time};
}
test('key allowance includes concurrent holds and blocks before a new reservation',()=>{
 const f=setup();
 f.ledger.setKeyLimits(f.account,f.key.id,{limitCredits:1,resetDays:null});
 const a=f.reserve();const b=f.reserve();
 assert.throws(()=>f.reserve(1),/key.*limit/i);
 f.settle(a);f.ledger.cancel(f.account,b.id);
 assert.equal(f.ledger.keyLimits(f.account,f.key.id).remainingCredits,.5);
 f.reserve();assert.throws(()=>f.reserve(1),/key.*limit/i);
 f.ledger.close();
});
test('daily and custom UTC periods reset without replenishing account funds',()=>{
 for(const days of [1,3,17]){
  const f=setup();f.ledger.setKeyLimits(f.account,f.key.id,{limitCredits:.5,resetDays:days});
  f.settle(f.reserve());assert.throws(()=>f.reserve(1),/key.*limit/i);
  const balance=f.ledger.summary(f.account).available;
  f.advance(days*day-day/2-1);assert.throws(()=>f.reserve(1),/key.*limit/i);
  f.advance(1);assert.equal(f.ledger.keyLimits(f.account,f.key.id).remainingCredits,.5);
  assert.equal(f.ledger.summary(f.account).available,balance);
  f.reserve();f.ledger.close();
 }
});
test('holds carry across reset and charge the period in which they settle',()=>{
 const f=setup();f.ledger.setKeyLimits(f.account,f.key.id,{limitCredits:.5,resetDays:1});
 const r=f.reserve();f.advance(day);
 assert.throws(()=>f.reserve(1),/key.*limit/i);f.settle(r);
 assert.throws(()=>f.reserve(1),/key.*limit/i);
 f.advance(day);f.reserve();f.ledger.close();
});
test('lifetime limits never reset, policy edits preserve spend and keys stay isolated',()=>{
 const f=setup();f.ledger.setKeyLimits(f.account,f.key.id,{limitCredits:.5,resetDays:null});
 f.settle(f.reserve());f.advance(4*day);
 f.ledger.setKeyLimits(f.account,f.key.id,{limitCredits:.5,resetDays:null});
 assert.throws(()=>f.reserve(1),/key.*limit/i);
 const other=f.ledger.issueKey(f.account);f.reserve(2500,other.id);
 const {account:outsider}=f.ledger.createSession();
 assert.throws(()=>f.ledger.setKeyLimits(outsider,f.key.id,{limitCredits:100}),/not found/i);
 assert.throws(()=>f.ledger.keyLimits(outsider,f.key.id),/not found/i);
 f.ledger.setKeyLimits(f.account,f.key.id,{limitCredits:1,resetDays:null});
 assert.equal(f.ledger.keyLimits(f.account,f.key.id).remainingCredits,.5);
 f.ledger.close();
});
test('expiry is terminal and checked again before provider submission',()=>{
 const f=setup();f.ledger.setKeyLimits(f.account,f.key.id,{expiresAt:f.now()+1000});
 const r=f.reserve();f.advance(1000);
 assert.equal(f.ledger.authenticate(f.key.key),undefined);
 assert.throws(()=>f.ledger.submit(r.id),/key/i);
 assert.throws(()=>f.ledger.setKeyLimits(f.account,f.key.id,{expiresAt:null}),/expired|inactive/i);
 f.ledger.close();
});
test('limits validate before issuing keys and optional never-expiring keys remain valid',()=>{
 const f=setup();const count=f.ledger.summary(f.account).keys.length;
 for(const value of [{limitCredits:-1},{limitCredits:.0001},{limitCredits:Infinity},{resetDays:0},{resetDays:1.5},{expiresAt:f.now()-1},{unknown:true}]){
  assert.throws(()=>f.ledger.issueKey(f.account,value));
 }
 assert.equal(f.ledger.summary(f.account).keys.length,count);
 const permanent=f.ledger.issueKey(f.account,{expiresAt:null,limitCredits:2,resetDays:3});
 f.advance(365*day);assert.ok(f.ledger.authenticate(permanent.key));
 f.ledger.close();
});
