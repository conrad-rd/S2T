import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { policies } from '../docs/legal/policies.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const operator = JSON.parse(readFileSync(resolve(root, 'docs/legal/operator.json'), 'utf8'));
const args = process.argv.slice(2);
const destinations = [];
let release = false;
for (let index = 0; index < args.length; index += 1) {
  if (args[index] === '--release') release = true;
  else if (args[index] === '--destination') {
    const destination = args[index + 1];
    if (!destination || destination.startsWith('--')) throw Error('Pass a directory after --destination.');
    destinations.push(resolve(root, destination));
    index += 1;
  }
  else throw Error(`Unknown or incomplete argument: ${args[index]}`);
}
if (!destinations.length) throw Error('Pass at least one explicit --destination directory.');
const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
if (release && !operator.address) throw Error('The legal notice needs Conrad Baulig’s confirmed business address before publication.');
const style = `:root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;line-height:1.65;background:#111;color:#ededed}*{box-sizing:border-box}body{margin:0}main,header,footer{max-width:780px;margin:auto;padding:24px}header{padding-top:40px}a{color:inherit;text-underline-offset:4px}nav{display:flex;flex-wrap:wrap;gap:12px 20px;margin:20px 0}nav a[aria-current=page]{font-weight:700}h1{font-size:clamp(28px,5vw,40px);line-height:1.2;letter-spacing:-.03em;margin:16px 0}h2{font-size:20px;margin:32px 0 8px}p{margin:10px 0;overflow-wrap:anywhere}.meta,footer{color:#bdbdbd;font-size:14px}.draft{border:1px solid #817454;padding:14px;border-radius:10px}address{font-style:normal}a:focus-visible{outline:2px solid currentColor;outline-offset:5px}.skip{position:absolute;top:-100px}.skip:focus{top:4px} @media print{:root{background:white;color:black}.meta,footer{color:#444}nav,.skip{display:none}main,header,footer{max-width:none;padding:12px}}`;
const contact = `<address>${escape(operator.name)}<br>${operator.address ? escape(operator.address).replaceAll('\n', '<br>') : 'Postal business address awaiting confirmation.'}<br><a href="mailto:${escape(operator.email)}">${escape(operator.email)}</a>${operator.phone ? `<br><a href="tel:${escape(operator.phone)}">${escape(operator.phone)}</a>` : ''}</address>`;
for (const destination of new Set(destinations)) {
  mkdirSync(destination, { recursive: true });
  writeFileSync(resolve(destination, 'policy.css'), style + '\n');
  for (const page of policies) {
    const nav = policies.map(item => `<a href="${item.slug}.html"${item.slug === page.slug ? ' aria-current="page"' : ''}>${escape(item.title)}</a>`).join('');
    const draft = operator.address ? '' : '<p class="draft">Temporary draft. The operator’s postal business address is still to be added.</p>';
    const body = (page.slug === 'refunds' ? '<p><a href="https://credits.s2t.app/withdraw.html">Withdraw a contract / Vertrag widerrufen</a>. The form sends an immediate downloadable receipt. It does not send a confirmation email.</p>' : '') + page.sections.map(([heading, text]) => `<section><h2>${escape(heading)}</h2><p>${escape(text)}</p></section>`).join('\n');
    writeFileSync(resolve(destination, `${page.slug}.html`), `<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer">${operator.address ? '' : '<meta name="robots" content="noindex">'}<title>${escape(page.title)} · S2T</title><link rel="icon" type="image/svg+xml" href="https://s2t.app/favicon.svg" /><link rel="stylesheet" href="policy.css"></head><body><a class="skip" href="#content">Skip to content</a><header><a href="https://s2t.app/" aria-label="S2T home">S2T</a><nav aria-label="Policies">${nav}</nav></header><main id="content"><h1>${escape(page.title)}</h1><p class="meta">Updated ${escape(operator.updated)}</p>${draft}${contact}${body}</main><footer>Keep a copy using your browser’s Save or Print command.</footer></body></html>\n`);
  }
}
console.log(`Generated ${policies.length} policy pages in ${new Set(destinations).size} explicit destination(s)${operator.address ? '' : ' as drafts pending the business address'}.`);
