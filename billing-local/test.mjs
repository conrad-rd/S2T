import test from 'node:test';
import assert from 'node:assert/strict';
import {createStore,hash} from './store.mjs';
test('purchase boundaries, exact conversion, duplicate delivery and account isolation',()=>{
 const s=createStore(':memory:');const token=s.create(), id=hash(token), other=hash(s.create());
 assert.throws(()=>s.key(id));
 for(const cents of [0,99,10001,1.5,NaN]) assert.throws(()=>s.credit(id,cents,'bad'));
 s.credit(id,500,'cs_test_one');s.credit(id,500,'cs_test_one');
 assert.equal(s.summary(id).balance,500);assert.equal(s.summary(other).balance,0);
 assert.throws(()=>s.credit(other,500,'cs_test_one'));assert.throws(()=>s.credit(id,600,'cs_test_one'));
 s.credit(id,100,'min');s.credit(id,10000,'max');assert.equal(s.summary(id).balance,10600);
 const key=s.key(id);assert.match(key,/^s2t_demo_[a-f0-9]{64}$/);assert.ok(!JSON.stringify(s.summary(id)).includes(key));
 assert.equal(s.summary(id).keys.length,1);s.close();
});
