import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { Readable } from 'node:stream';
import { createApplication } from '../server.mjs';
import { configuration } from '../config.mjs';

test('retired streaming endpoints expose neither tokens nor client duration settlement', async()=>{
  const config=configuration({S2T_BILLING_MODE:'demo',S2T_BILLING_DATA_DIR:mkdtempSync(tmpdir()+'/s2t-stream-retired-')});
  const app=createApplication(config);
  const account=app.ledger.createSession().account;
  app.ledger.grant({account,cents:500,session:'fixture',intent:'fixture'});
  const key=app.ledger.issueKey(account).key;
  const call=async(path,body)=>{
    const req=Readable.from(body === undefined ? [] : [JSON.stringify(body)]);
    req.url=path;req.method=body === undefined ? 'GET' : 'POST';
    req.headers={host:new URL(config.origin).host,authorization:`Bearer ${key}`,'content-type':'application/json','idempotency-key':'retired-fixture'};
    req.socket={remoteAddress:'127.0.0.1'};
    const response={destroyed:false,headers:{},setHeader(name,value){this.headers[name]=value;},writeHead(status){this.status=status;},end(data){this.body=data?.toString() || '';}};
    await app.server.listeners('request')[0](req,response);
    return {status:response.status,json:async()=>JSON.parse(response.body)};
  };
  try {
    const balance=await call('/api/v1/balance');
    assert.equal(balance.status,200);
    assert.equal('assemblyStreaming' in await balance.json(),false);
    assert.equal((await call('/api/v1/streaming/sessions',{maxSeconds:'630'})).status,404);
    assert.equal((await call('/api/v1/streaming/sessions/missing/complete',{sessionDurationSeconds:'0'})).status,404);
    assert.equal((await call('/api/v1/streaming/sessions/missing/abandon',{})).status,404);
    assert.equal((await call('/api/v1/streaming/sessions/cancel',{})).status,404);
  } finally {await app.close();}
});

test('old streaming environment switch cannot silently reenable insecure issuance',()=>{
  assert.throws(()=>configuration({S2T_BILLING_MODE:'demo',S2T_ASSEMBLY_STREAMING:'private-beta'}),{code:'streaming_retired'});
});
