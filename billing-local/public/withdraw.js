const form=document.getElementById('withdraw-form');
const status=document.getElementById('withdraw-status');
const confirmation=document.getElementById('confirmation');
let submissionId=crypto.randomUUID();
const value=()=>({id:submissionId,name:form.elements.name.value.trim(),email:form.elements.email.value.trim(),contract:form.elements.contract.value.trim(),delivery:'download',confirmed:true});
form.addEventListener('input',()=>{confirmation.hidden=true;submissionId=crypto.randomUUID();});
form.addEventListener('submit',event=>{
  event.preventDefault();if(!form.reportValidity())return;
  const data=value();document.getElementById('review-details').textContent=`Name: ${data.name}\nEmail: ${data.email}\nPurchase: ${data.contract}\nReceipt: text file download`;
  confirmation.hidden=false;document.getElementById('confirm-title').focus();
});
document.getElementById('confirm').addEventListener('click',async()=>{
  if(!form.reportValidity())return;
  const controls=[...form.querySelectorAll('input,button')];controls.forEach(control=>control.disabled=true);
  status.textContent='Submitting your withdrawal…';
  try {
    const response=await fetch('/api/withdrawals',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(value())});
    const result=await response.json();if(!response.ok)throw Error(result.error||'Submission failed.');
    const link=document.getElementById('receipt');
    link.href=URL.createObjectURL(new Blob([result.receipt],{type:'text/plain;charset=utf-8'}));
    link.download=`S2T-withdrawal-${result.id}.txt`;link.hidden=false;link.click();
    status.textContent=`Your withdrawal was received at ${result.receivedAt}. Save the receipt. If the download did not start, use the link below. No refund has been issued yet.`;
    form.hidden=true;link.focus();
  } catch(error) {
    status.textContent=`We could not confirm receipt. ${error.message} Retry with this form, or email info@conrad-baulig.com before your deadline.`;
    controls.forEach(control=>control.disabled=false);
  }
});
