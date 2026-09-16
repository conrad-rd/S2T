import { randomBytes, createHmac } from 'node:crypto';
import { hash } from './ledger-core.mjs';
import { requireThat } from './money.mjs';
export function createDeviceLink({ ledger, mode, encryptionKey, origin }) {
  const deriveKey = tokenHash => `s2t_${mode}_` + createHmac('sha256', encryptionKey).update('s2t-device-key-v1:' + tokenHash).digest('hex');
  return {
    start() {
      const deviceCode = randomBytes(32).toString('hex');
      const userCode = randomBytes(6).toString('hex').toUpperCase();
      ledger.startDevice(hash(deviceCode), userCode);
      return { deviceCode, userCode, verificationURL: `${origin}/?connect=${userCode}`, expiresIn: 600 };
    },
    approve(account, userCode) {
      requireThat(typeof userCode === 'string' && /^[A-F0-9]{12}$/.test(userCode), 'device_code', 'Invalid connection code.');
      ledger.approveDevice(account, userCode, deriveKey);
      return { approved: true };
    },
    poll(deviceCode) {
      requireThat(typeof deviceCode === 'string' && /^[a-f0-9]{64}$/.test(deviceCode), 'device_code', 'Invalid device token.', 401);
      const tokenHash = hash(deviceCode);
      const link = ledger.device(tokenHash);
      if (!link.account) return { state: 'pending' };
      const key = deriveKey(tokenHash);
      requireThat(ledger.authenticate(key)?.id === link.key_id, 'device_revoked', 'This connection has been revoked.', 401);
      return { state: 'approved', key };
    },
  };
}
