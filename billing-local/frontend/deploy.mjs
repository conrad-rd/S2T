import { cpSync, existsSync, mkdtempSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const staging = mkdtempSync(join(tmpdir(), 's2t-credits-frontend-'));
try {
  cpSync(new URL('../public/', import.meta.url), join(staging, 'source'), { recursive: true });
  for (const name of ['build.mjs', 'vercel.json', '.vercelignore']) {
    cpSync(new URL(`./${name}`, import.meta.url), join(staging, name));
  }
  const project = new URL('./.vercel/', import.meta.url);
  if (existsSync(project)) cpSync(project, join(staging, '.vercel'), { recursive: true });
  const build = spawnSync(process.execPath, ['build.mjs'], { cwd: staging, stdio: 'inherit' });
  if (build.status !== 0) throw Error(`Frontend build failed${build.signal ? ` with ${build.signal}` : ` with status ${build.status}`}.`);
  const scope = process.env.VERCEL_SCOPE ? ['--scope', process.env.VERCEL_SCOPE] : [];
  const deploy = spawnSync('npx', ['--yes', 'vercel', '--prod', '--yes', ...scope], { cwd: staging, stdio: 'inherit' });
  if (deploy.status !== 0) throw Error(`Vercel deployment failed${deploy.signal ? ` with ${deploy.signal}` : ` with status ${deploy.status}`}.`);
} finally {
  rmSync(staging, { recursive: true, force: true });
}
