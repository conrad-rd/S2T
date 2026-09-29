import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { requireThat } from './money.mjs';

export function createWithdrawals({ledger, encryptionKey, confirmSaved=async()=>{}}) {
  requireThat(Buffer.isBuffer(encryptionKey) && encryptionKey.length===32,'config','Withdrawal encryption is not configured.');
  function decrypt(row) {
    const bytes=Buffer.from(row.payload,'base64');
    const cipher=createDecipheriv('aes-256-gcm',encryptionKey,bytes.subarray(0,12));
    cipher.setAAD(Buffer.from('s2t-withdrawal:'+row.id));cipher.setAuthTag(bytes.subarray(12,28));
    return JSON.parse(Buffer.concat([cipher.update(bytes.subarray(28)),cipher.final()]).toString());
  }
  return {
    async submit(value) {
      requireThat(value && typeof value==='object','withdrawal','Provide withdrawal details.');
      requireThat(typeof value.id==='string' && /^[a-f0-9-]{36}$/.test(value.id),'withdrawal','Invalid submission identifier.');
      const field=(key,max)=>{
        const text=value[key];
        requireThat(typeof text==='string' && text.trim().length>0 && text.length<=max && !/[\x00-\x1f\x7f]/.test(text),'withdrawal',`Provide a valid ${key}.`);
        return text.trim();
      };
      const name=field('name',200),email=field('email',254),contract=field('contract',1000);
      requireThat(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email),'withdrawal','Provide a valid email.');
      requireThat(value.confirmed===true && value.delivery==='download','withdrawal','Please confirm withdrawal and receipt download.');
      const fingerprint=createHash('sha256').update(JSON.stringify([name,email,contract,value.delivery])).digest('hex');
      const receivedAt=new Date().toISOString();
      const receipt=`S2T withdrawal receipt / Eingangsbestätigung\n\nReference: ${value.id}\nReceived: ${receivedAt} UTC\nConsumer: ${name}\nEmail: ${email}\nContract or part withdrawn: ${contract}\nDeclaration: I withdraw from the contract or part identified above.\nConfirmation delivery chosen: text file download in this browser.\n\nReceived by Conrad Baulig, Boisseréestraße 1, 50674 Köln, Deutschland.\nContact: info@conrad-baulig.com, +4915123203112\n\nThis confirms receipt of your declaration. It does not yet confirm a refund. Statutory deadlines and rights remain unchanged. Keep this file.\n`;
      const result={id:value.id,receivedAt,receipt};
      const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',encryptionKey,iv);
      cipher.setAAD(Buffer.from('s2t-withdrawal:'+value.id));
      const encrypted=Buffer.concat([cipher.update(Buffer.from(JSON.stringify(result))),cipher.final()]);
      const payload=Buffer.concat([iv,cipher.getAuthTag(),encrypted]).toString('base64');
      const stored=ledger.submitWithdrawal(value.id,fingerprint,payload);
      await confirmSaved();
      return decrypt(stored);
    },
    list() { return ledger.withdrawals().map(decrypt); },
  };
}
