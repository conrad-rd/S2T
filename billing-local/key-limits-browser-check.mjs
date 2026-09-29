import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {once} from 'node:events';
import {createApplication} from './server.mjs';
import {configuration} from './config.mjs';
const config=configuration({S2T_BILLING_DATA_DIR:mkdtempSync(tmpdir()+'/s2t-limits-browser-')});
const app=createApplication(config);app.server.listen(0,'127.0.0.1');await once(app.server,'listening');config.port=app.server.address().port;config.origin=`http://localhost:${config.port}`;
const browser=await chromium.launch({channel:'chrome',headless:true});
try{
 const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 if(process.env.S2T_LIMITS_ORIGIN) await page.route('**/api/**',async route=>{
  const request=route.request();const url=new URL(request.url());
  const response=await route.fetch({url:config.origin+url.pathname+url.search,headers:{...request.headers(),origin:config.origin}});
  return route.fulfill({response});
 });
 if(process.env.S2T_LIMITS_ASSETS) await page.route('**/*',async route=>{
  const path=new URL(route.request().url()).pathname;
  if(['/', '/index.html','/app.js','/style.css'].includes(path)) return route.fulfill({body:readFileSync(resolve(process.env.S2T_LIMITS_ASSETS,path==='/'?'index.html':path.slice(1))),contentType:path.endsWith('.js')?'application/javascript':path.endsWith('.css')?'text/css':'text/html'});
  return route.continue();
 });
 await page.goto((process.env.S2T_LIMITS_ORIGIN || config.origin)+'/#keys-details');await page.locator('#account-content').waitFor({state:'visible'});
 assert.equal(await page.locator('#keys-details').isVisible(),true);
 await page.locator('.new-key-options > summary').click();
 const form=page.locator('#new-key-settings form');
 await form.getByLabel('Credit limit',{exact:true}).fill('12.5');await form.getByLabel('Reset allowance').selectOption('3');await form.getByLabel('Key expires',{exact:true}).selectOption('never');
 await page.getByRole('button',{name:'Create demo key'}).click();await page.locator('#key-value').waitFor({state:'visible'});
 assert.match(await page.locator('.key-limit-summary').textContent(),/12.5.*Resets every 3 days/);
 await page.locator('.key-limit-details > summary').click();let existing=page.locator('#key-list form');
 await existing.getByLabel('Reset allowance').selectOption('custom');await existing.getByLabel('Days between resets').fill('17');
 await Promise.all([page.waitForResponse(response=>response.url().includes('/api/account')),page.evaluate(()=>window.dispatchEvent(new Event('focus')))]);
 assert.equal(await existing.getByLabel('Days between resets').inputValue(),'17');
 await existing.getByLabel('Credit limit',{exact:true}).fill('8');await existing.getByLabel('Credit limit',{exact:true}).press('Enter');
 await page.waitForFunction(()=>document.querySelector('.key-limit-summary').textContent.includes('17 days'));
 await page.reload();await page.locator('.key-limit-details > summary').click();existing=page.locator('#key-list form');assert.equal(await existing.getByLabel('Days between resets').inputValue(),'17');
 for(const width of [320,375,768,1280]){await page.setViewportSize({width,height:900});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,`Overflow ${width}`);}
 await existing.getByLabel('Credit limit',{exact:true}).fill('');await existing.getByLabel('Key expires',{exact:true}).selectOption('after');await existing.getByLabel('Days until expiry').fill('3');await existing.getByRole('button',{name:'Save limits'}).click();
 await page.waitForFunction(()=>document.querySelector('.key-limit-summary').textContent.includes('No key credit limit'));assert.match(await page.locator('.key-limit-summary').textContent(),/Expires/);
 await page.getByRole('button',{name:/Revoke key ending/}).click();await page.waitForFunction(()=>!document.querySelector('.key-row'));
 const fixture=await (await fetch(config.origin+'/api/account')).json();
 let paused=true;
 await page.route('**/api/account*',route=>route.fulfill({json:{...fixture,paused,keys:[{id:'expired',suffix:'1234',expires:Date.now()-60000,limits:{limitCredits:5,remainingCredits:0,expiresAt:Date.now()-60000}}]}}));
 await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
 await page.locator('#account-warning').waitFor({state:'visible'});
 assert.match(await page.locator('#account-warning').textContent(),/Changing key limits will not resume usage/);
 await page.waitForFunction(()=>document.querySelector('.key-limit-summary')?.textContent==='Expired permanently');
 assert.equal(await page.locator('#key-list form').count(),0);
 paused=false;await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
 await page.locator('#account-warning').waitFor({state:'hidden'});
 await page.evaluate(()=>{location.hash='';window.scrollTo(0,0)});
 await page.waitForFunction(()=>location.hash==='');
 await page.evaluate(()=>{location.hash='keys-details'});
 await page.waitForFunction(()=>{const rect=document.getElementById('keys-details').getBoundingClientRect();return rect.top>=0&&rect.top<innerHeight});
 assert.deepEqual(errors,[]);console.log('PASS: issuance, custom intervals, Enter submission, expiry, unlimited allowance, drafts across refresh, revoke, service pause, terminal expiry, limits link and responsive forms. No screenshots.');
}finally{await browser.close();await app.close();}
