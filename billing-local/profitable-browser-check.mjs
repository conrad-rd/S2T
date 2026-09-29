import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync } from 'node:fs';
import { extname } from 'node:path';
import { once } from 'node:events';
import { configuration } from './config.mjs';
import { createApplication } from './server.mjs';
const stage=readFileSync('../build/profitable-pricing/stage-path.txt','utf8').trim();
const config=configuration({S2T_BILLING_DATA_DIR:mkdtempSync('/private/tmp/s2t-profit-browser-')});
const app=createApplication(config);app.server.listen(0,'127.0.0.1');await once(app.server,'listening');
config.origin=`http://localhost:${app.server.address().port}`;
const origin=process.env.S2T_DASHBOARD_ORIGIN||config.origin;
const live=!!process.env.S2T_DASHBOARD_ORIGIN;
const browser=await chromium.launch({channel:'chrome',headless:true});
const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
try{
 if(live)await page.route('**/api/**',async route=>{const u=new URL(route.request().url());const response=await route.fetch({url:config.origin+u.pathname+u.search,headers:{...route.request().headers(),origin:config.origin}});await route.fulfill({response});});
 else await page.route('**/*',async route=>{
  const path=new URL(route.request().url()).pathname;if(path.startsWith('/api/'))return route.fallback();
  const file=path==='/'?'index.html':path.slice(1);const types={'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.ttf':'font/ttf'};
  await route.fulfill({body:readFileSync(stage+'/credits/public/'+file),contentType:types[extname(file)]||'application/octet-stream'});
 });
 await page.goto(origin);await page.waitForFunction(()=>!document.querySelector('#account-content').hidden);
 assert.match(await page.locator('details').filter({hasText:'Credit pricing'}).textContent(),/\$0\.005/);
 await page.locator('#open-purchase').click();
 assert.equal(await page.locator('#amount').getAttribute('min'),'5');
 assert.deepEqual(await page.locator('[data-amount]').evaluateAll(nodes=>nodes.map(n=>n.dataset.amount)),['5','10','20','50']);
 for(const value of ['1','2','3','4.99','100.01']){await page.locator('#amount').fill(value);assert.equal(await page.locator('#purchase').isDisabled(),true);}
 for(const value of ['5','5.01','10','20','50','100']){await page.locator('#amount').fill(value);assert.equal(await page.locator('#purchase').isEnabled(),true);}
 await page.locator('#amount').fill('5');await page.locator('#purchase').click();
 await page.waitForFunction(()=>document.querySelector('#balance').textContent==='500.0000');
 await page.getByRole('button',{name:'Try a metered demo request'}).click();
 await page.waitForFunction(()=>document.querySelector('#balance').textContent==='499.9820');
 await page.locator('#activity-details>summary').click();
 assert.match(await page.locator('#requests').textContent(),/0\.0180 credits/);
 for(const width of [320,375,768,1280]){await page.setViewportSize({width,height:900});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);}
 assert.deepEqual(errors,[]);console.log('PASS exact dashboard: $5 minimum, presets, 100 credits/$, $0.005 usage conversion, metering and responsive DOM. APIs isolated, no screenshots or real payments.');
}finally{await browser.close();await app.close();}
