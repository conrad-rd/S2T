import { chromium } from 'playwright';
import { setupClerkTestingToken } from '@clerk/testing/playwright';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const origin = process.env.S2T_TEST_ORIGIN;
const app = process.env.CLERK_TEST_APP_ID, user = process.env.CLERK_TEST_USER_ID;
assert.ok(origin && app && user && process.env.CLERK_FAPI, 'Set S2T_TEST_ORIGIN, CLERK_TEST_APP_ID, CLERK_TEST_USER_ID, and CLERK_FAPI for your dedicated test instance.');
const api = (path, data) => JSON.parse(execFileSync('clerk', ['api',path,'--app',app,...(data ? ['-d',JSON.stringify(data),'--yes'] : [])], {encoding:'utf8',stdio:['pipe','pipe','pipe']}));
const testUser=api('/users/'+user);
assert.ok(testUser.email_addresses.some(e=>e.email_address.includes('clerk_test')),'Only the dedicated Clerk test user may be used.');
const testing = api('/testing_tokens',{}), signIn = api('/sign_in_tokens',{user_id:user,expires_in_seconds:600});
process.env.CLERK_TESTING_TOKEN=testing.token;
const browser = await chromium.launch({headless:true});
const page = await browser.newPage();
const failures=[];
page.on('pageerror',e=>failures.push(e.message));
try {
 await setupClerkTestingToken({page});
 const start=await (await fetch(origin+'/api/device/start',{method:'POST'})).json();
 assert.ok(start.deviceCode,'Device sign-in must be available.');
 await page.goto(start.verificationURL);
 await page.waitForFunction(()=>window.Clerk?.loaded,{timeout:30000});
 await page.evaluate(async ticket=>{
   const attempt=await window.Clerk.client.signIn.create({strategy:'ticket',ticket});
   if(attempt.status!=='complete')throw Error('Test sign-in incomplete');
   await window.Clerk.setActive({session:attempt.createdSessionId});
 },signIn.token);
 await page.locator('#account-content').waitFor({state:'visible',timeout:20000});
 await page.locator('#connect-approve').click();
 await page.locator('#connect-status').filter({hasText:'Connected.'}).waitFor({timeout:15000});
 const result=await (await fetch(origin+'/api/device/poll',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({deviceCode:start.deviceCode})})).json();
 assert.equal(result.state,'approved');
 const balance=await (await fetch(origin+'/api/v1/balance',{headers:{Authorization:'Bearer '+result.key}})).json();
 assert.equal(balance.mode,'test');
 assert.ok(Number.isFinite(balance.available));
 const token=await page.evaluate(()=>window.Clerk.session.getToken({template:'s2t'}));
 mkdirSync('../build/credits-cloudflare',{recursive:true,mode:0o700});
 writeFileSync('../build/credits-cloudflare/test-session.json',JSON.stringify({key:result.key,token,user,origin}),{mode:0o600});
 assert.deepEqual(failures,[]);
 console.log('PASS: hosted Cloudflare service, real Clerk test-account sign-in, JWT audience validation, browser-approved Mac connection, and authenticated balance. No screenshots or user clipboard.');
 console.log('Checkout enabled:',await page.locator('#purchase').isEnabled());
} catch(error) {
 console.log('Hosted test failed:',error.message.split('\n')[0]);
 console.log('Page status:',await page.locator('#status').textContent({timeout:1000}).catch(()=>''));
 console.log('Browser errors:',failures.map(x=>x.slice(0,250)));
 process.exitCode=1;
} finally {await browser.close();}
