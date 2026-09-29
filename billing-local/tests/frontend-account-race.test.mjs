import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const source=readFileSync(fileURLToPath(new URL('../public/app.js',import.meta.url)),'utf8');
const slice=(start,end)=>{
  const first=source.indexOf(start),last=source.indexOf(end,first);
  assert.ok(first>=0 && last>first,`Handler boundary missing: ${start}`);
  return source.slice(first,last);
};
const keyHandler=slice('$("create-key").addEventListener("click", async () => {','$("copy-key").addEventListener');
const listener=slice('clerk.addListener(({ user }) => {','    if (!clerk.user)');
const refreshFunction=slice('async function refresh() {','function renderUsage(');

function fakeDOM() {
  const nodes=new Map();
  const node=id=>{
    if(!nodes.has(id)) nodes.set(id,{hidden:true,value:'',disabled:false,textContent:'',
      addEventListener(_,callback){this.callback=callback;},replaceChildren(){},close(){}});
    return nodes.get(id);
  };
  return {node,nodes};
}

test('delayed create-key response cannot reveal the former account key after Clerk switches users',async()=>{
  const {node}=fakeDOM();
  let resolveRequest;
  const request=new Promise(resolve=>{resolveRequest=resolve;});
  const notices=[];
  const clerk={addListener(callback){this.listener=callback;},unmountSignIn(){},mountUserButton(){},mountSignIn(){}};
  const context=vm.createContext({$:node,clerk,api:()=>request,newKeyForm:{readLimits:()=>({})},refresh:async()=>{},
    status:value=>notices.push(value),account:null,identityGeneration:0,refreshGeneration:0,purchaseAttempt:null,
    chartSignature:'',usageDays:30});
  vm.runInContext('class StaleIdentity extends Error {}\nlet lastUser;\n'+listener+keyHandler,context);
  clerk.listener({user:{id:'account-A'}});
  context.account={mode:'live',id:'account-A'};
  const completion=node('create-key').callback();
  assert.equal(node('create-key').disabled,true);
  node('connect-approve').disabled=true;
  node('connect-status').textContent='Connecting account A';
  clerk.listener({user:{id:'account-B'}});
  context.account={mode:'live',id:'account-B'};
  notices.length=0;
  resolveRequest({key:'fixture-secret-for-account-A'});
  await completion;
  assert.equal(node('key-result').hidden,true);
  assert.equal(node('key-value').value,'');
  assert.equal(node('create-key').disabled,false);
  assert.equal(node('connect-approve').disabled,false);
  assert.equal(node('connect-status').textContent,'');
  assert.deepEqual(notices,[]);
  context.api=async()=>({key:'fixture-secret-for-account-B'});
  await node('create-key').callback();
  assert.equal(node('key-result').hidden,false);
  assert.equal(node('key-value').value,'fixture-secret-for-account-B');
});

test('stale identity refresh is swallowed before older async error can clear new account status',async()=>{
  const {node}=fakeDOM();
  const context=vm.createContext({$:node,document:{querySelector:()=>({setAttribute(){},removeAttribute(){}})},
    api:async()=>{throw new Error('replace');},refreshGeneration:0,usageDays:30});
  vm.runInContext('class StaleIdentity extends Error {}\n'+refreshFunction,context);
  context.api=async()=>{throw vm.runInContext('new StaleIdentity()',context);};
  let errorMessage='new account is ready';
  await context.refresh().catch(error=>{errorMessage=error.message;});
  assert.equal(errorMessage,'new account is ready');
});
