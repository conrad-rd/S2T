import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createApplication } from './server.mjs';
import { configuration } from './config.mjs';
const config = configuration({ S2T_BILLING_DATA_DIR: mkdtempSync(tmpdir() + '/s2t-native-') });
const app = createApplication(config);
app.server.listen(0, '127.0.0.1');
await once(app.server, 'listening');
config.port = app.server.address().port;
config.origin = `http://127.0.0.1:${config.port}`;
try {
  const { account } = app.ledger.createSession();
  app.ledger.grant({ account, cents: 500, session: 'native-demo-payment', intent: 'native-demo-payment' });
  const { key } = app.ledger.issueKey(account);
  const child = spawn(fileURLToPath(new URL('../build/S2T.app/Contents/MacOS/S2T', import.meta.url)), ['--verify-credits-http'], {
    env: { ...process.env, S2T_CREDITS_FIXTURE_ORIGIN: config.origin, S2T_CREDITS_FIXTURE_KEY: key }, stdio: ['ignore', 'inherit', 'inherit'],
  });
  const timer = setTimeout(() => child.kill('SIGTERM'), 30000);
  const [code] = await once(child, 'exit');
  clearTimeout(timer);
  if (code !== 0) throw Error('Native credit verification failed');
  assert.equal(app.ledger.summary(account).available, 499.99);
  assert.equal(app.ledger.summary(account).requests.length, 1);
} finally { await app.close(); }
