import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const cwd = dirname(fileURLToPath(import.meta.url));
if (process.argv.length !== 3) throw Error('Usage: npm run test:release -- /absolute/path/to/worker.js');
const artifact = resolve(process.argv[2]);
const app = resolve(cwd, '../build/S2T.app/Contents/MacOS/S2T');
const digest = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const before = { workerSHA256: digest(artifact), appSHA256: digest(app) };
const env = { ...process.env, S2T_DEPLOYMENT_ARTIFACT: artifact, S2T_STREAMING_BUNDLE: artifact };
async function run(command, args) {
  console.log('VERIFY', command, ...args);
  await new Promise((ok, fail) => {
    const child = spawn(command, args, { cwd, env, stdio: 'inherit' });
    const timer = setTimeout(() => { child.kill('SIGTERM'); fail(Error('Verification timed out')); }, 120000);
    child.once('error', error => { clearTimeout(timer); fail(error); });
    child.once('exit', (code, signal) => {
      clearTimeout(timer);
      if (code === 0) ok(); else fail(Error(`Verification failed: ${command}, exit ${code}, signal ${signal}`));
    });
  });
}
await run('npm', ['test']);
await run(app, ['--verify-build']);
await run(app, ['--verify-credits']);
await run(app, ['--verify-early-transcription']);
for (const check of ['billing-audit-deployment-check.mjs', 'openrouter-catalog-deployment-check.mjs', 'profitable-deployment-check.mjs', 'volume-deployment-check.mjs', 'streaming-retirement-cloudflare-check.mjs', 'storage-maintenance-deployment-check.mjs']) {
  await run(process.execPath, [check]);
}
if (digest(artifact) !== before.workerSHA256 || digest(app) !== before.appSHA256) {
  throw Error('App or Worker changed during verification. Verify the final artifacts again.');
}
writeFileSync(artifact + '.verified.json', JSON.stringify({ ...before, verifiedAt: new Date().toISOString(),
  syntheticProviders: true, liveInferenceTested: false }, null, 2) + '\n');
console.log('PASS release check. Exact app and Worker hashes recorded. Providers and payments were simulated.');
