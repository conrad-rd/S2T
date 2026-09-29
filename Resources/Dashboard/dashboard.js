'use strict';
const $ = id => document.getElementById(id);
let snapshot = { records: [], startedAt: new Date().toISOString(), error: '' };
let source = 's2t', days = 30, chosenSource = false;
const names = {s2t:'S2T credits',openRouter:'OpenRouter',assemblyAI:'AssemblyAI'};
const number = value => Number(value).toLocaleString('en-US',{minimumFractionDigits:4,maximumFractionDigits:4});
const amount = value => (source === 's2t' ? '' : '$') + number(value);
const date = value => new Date(value).toLocaleDateString(undefined,{month:'short',day:'numeric',timeZone:'UTC'});
function amountText(text) {
  const span = document.createElement('span');
  for (const part of text.split(/(?<=\d)(\.\d+)/)) {
    if (/^\.\d+$/.test(part)) { const decimal = document.createElement('span'); decimal.className = 'decimal-places'; decimal.textContent = part; span.append(decimal); }
    else span.append(part);
  }
  return span;
}
function setAmount(id, value) { $(id).replaceChildren(amountText(amount(value))); }
function render() {
  const records = snapshot.records.filter(r => r.source === source);
  const complete = records.filter(r => !r.pending);
  const sum = rows => rows.reduce((total,r) => total + Number(r.amount ?? 0),0);
  const known = complete.filter(r => r.amount != null);
  setAmount('balance',sum(known));
  $('balance').setAttribute('aria-label', `${amount(sum(known))} ${source === 's2t' ? 'credits' : 'USD'} used on this Mac`);
  $('total-label').textContent = source === 's2t' ? 'credits used on this Mac' : source === 'assemblyAI' ? 'estimated USD used on this Mac' : 'reported USD used on this Mac';
  const pending = records.filter(r => r.pending);
  $('held-balance').hidden = !pending.length;
  $('held-balance').replaceChildren(amountText(`${number(sum(pending))} credits pending confirmation`));
  const last = complete[0];
  $('last-used').textContent = last ? date(last.date) : 'No usage yet';
  $('last-used-detail').textContent = last ? new Date(last.date).toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit',timeZone:'UTC'}) + ' UTC' : '';
  $('tracking-since').textContent = date(snapshot.startedAt);
  $('storage-warning').textContent = snapshot.error; $('storage-warning').hidden = !snapshot.error;
  $('estimate-note').hidden = source !== 'assemblyAI';
  for (const button of document.querySelectorAll('[data-source]')) button.setAttribute('aria-pressed',button.dataset.source === source);
  for (const button of document.querySelectorAll('[data-days]')) button.setAttribute('aria-pressed',Number(button.dataset.days) === days);
  const today = new Date(); today.setUTCHours(0,0,0,0);
  const start = today.getTime() - (days - 1) * 86400000;
  const period = complete.filter(r => new Date(r.date).getTime() >= start && new Date(r.date).getTime() < today.getTime()+86400000);
  setAmount('usage-total',sum(period));
  $('usage-unit').textContent = source === 's2t' ? 'credits used' : source === 'assemblyAI' ? 'USD estimated' : 'USD used';
  $('chart-unit').textContent = source === 's2t' ? 'Credits' : source === 'assemblyAI' ? 'USD · estimated' : 'USD';
  const series = Array.from({length:days},(_,i) => {
    const day = start+i*86400000;
    const items = period.filter(r => Math.floor(new Date(r.date).getTime()/86400000) === Math.floor(day/86400000));
    return {date:day,value:sum(items),count:items.length};
  });
  const max = Math.max(...series.map(d => d.value));
  const chart = $('usage-chart'); chart.replaceChildren(); chart.style.gridTemplateColumns = `repeat(${days},minmax(0,1fr))`;
  $('chart-detail').hidden = true;
  $('chart-y-axis').replaceChildren();
  for (const fraction of max >= .0004 ? [1,.75,.5,.25,0] : max ? [1,0] : [0]) {
    const tick = document.createElement('span'); tick.append(amountText(number(max*fraction))); tick.style.top = `${(1-fraction)*100}%`; $('chart-y-axis').append(tick);
  }
  const strokes = Array.from({length:28},(_,row) => `M2 ${220-row*8}h20a2 2 0 0 1 0 4H2a2 2 0 0 1 0-4Z`).join('');
  series.forEach((day,index) => {
    const button = document.createElement('button'); button.className='chart-day'; button.dataset.empty=day.value===0; button.tabIndex=index===days-1?0:-1;
    const label = `${date(day.date)} · ${amount(day.value)} ${source==='s2t'?'credits':'USD'} · ${day.count} requests`;
    button.setAttribute('aria-label',label);
    const bar = document.createElement('span'); bar.className='chart-bar'; bar.style.setProperty('--height',`${max?day.value/max*100:0}%`); bar.setAttribute('aria-hidden','true');
    const marks = document.createElementNS('http://www.w3.org/2000/svg','svg'); marks.setAttribute('viewBox','0 0 24 224'); marks.setAttribute('preserveAspectRatio','none'); marks.classList.add('chart-strokes');
    const path = document.createElementNS(marks.namespaceURI,'path'); path.setAttribute('d',strokes); marks.append(path); bar.append(marks); button.append(bar);
    const describe = () => { for(const child of chart.children) delete child.dataset.active; button.dataset.active='true'; $('chart-detail').replaceChildren(amountText(label)); $('chart-detail').hidden=false; };
    button.onmouseenter=describe; button.onfocus=describe;
    button.onkeydown=event => { const next = event.key==='ArrowLeft'?index-1:event.key==='ArrowRight'?index+1:event.key==='Home'?0:event.key==='End'?days-1:null;
      if(next!==null){event.preventDefault(); const target=chart.children[Math.max(0,Math.min(days-1,next))]; for(const child of chart.children) child.tabIndex=-1; target.tabIndex=0; target.focus();}
    };
    chart.append(button);
  });
  chart.onmouseleave=() => { if(!chart.contains(document.activeElement)) $('chart-detail').hidden=true; };
  chart.onfocusout=event => { if(!chart.contains(event.relatedTarget)) $('chart-detail').hidden=true; };
  $('usage-empty').hidden=!!max;
  $('usage-empty').textContent=!complete.length?'Usage will appear after your first request.':period.some(r=>r.amount==null)?'No reported cost for this period.':'No usage in this period.';
  $('chart-start').textContent=date(start); $('chart-end').textContent=date(today);
  const missing=period.filter(r=>r.amount==null).length;
  const tokenCount=period.reduce((n,r)=>n+(r.tokens??0),0);
  const seconds=period.reduce((n,r)=>n+(r.seconds??0),0);
  $('coverage').textContent=[missing?`${missing} request${missing===1?'':'s'} without a reported cost, excluded from totals.`:'',source==='openRouter'&&tokenCount?`${tokenCount.toLocaleString()} tokens`:'',source==='assemblyAI'&&seconds?`${(seconds/60).toFixed(1)} audio minutes`:''].filter(Boolean).join(' ');
  $('activity-count').textContent=complete.length.toLocaleString(); $('requests').replaceChildren();
  for(const r of complete.slice(0,25)){
    const row=document.createElement('div'); row.className='transaction';
    const info=document.createElement('div'); info.textContent=names[source]; const when=document.createElement('small'); when.textContent=date(r.date)+' · '+new Date(r.date).toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit',timeZone:'UTC'})+' UTC'; info.append(when);
    const value=document.createElement('strong'); value.append(amountText(r.amount==null?'Cost unavailable':amount(r.amount)+(r.estimated?' estimated':''))); row.append(info,value); $('requests').append(row);
  }
  if(!complete.length) $('requests').textContent='No recorded usage yet.';
}
window.updateUsage = value => { snapshot=value; if(!chosenSource && snapshot.records.length){source=snapshot.records[0].source;chosenSource=true;} render(); };
for(const button of document.querySelectorAll('[data-source]')) button.onclick=()=>{source=button.dataset.source;chosenSource=true;render();};
for(const button of document.querySelectorAll('[data-days]')) button.onclick=()=>{days=Number(button.dataset.days);render();};
render();
