import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  cp,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, parse } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const buildScript = fileURLToPath(new URL('../frontend/build.mjs', import.meta.url));

const createSource = async (source, extraFiles = {}) => {
  await mkdir(join(source, 'policies'), { recursive: true });
  await writeFile(join(source, 'index.html'), '<h1>index-v1</h1>\n');
  await writeFile(join(source, 'policies', 'privacy.html'), '<h1>privacy</h1>\n');
  for (const [path, contents] of Object.entries(extraFiles)) {
    const target = join(source, path);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, contents);
  }
};

const runBuild = (source, output) => spawnSync(
  process.execPath,
  [buildScript, '--source', source, '--output', output],
  { encoding: 'utf8' },
);

const failureText = (result) => `${result.stdout ?? ''}\n${result.stderr ?? ''}`;

test('frontend build rejects unsafe and overlapping destinations before changing them', async (t) => {
  const temporary = await mkdtemp(join(tmpdir(), 's2t-frontend-destination-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));

  const source = join(temporary, 'source');
  await createSource(source);

  const rootResult = runBuild(source, parse(temporary).root);
  assert.notEqual(rootResult.status, 0, failureText(rootResult));
  assert.match(failureText(rootResult), /dedicated directory named public/);

  const arbitraryOutput = join(temporary, 'shared-data');
  await mkdir(arbitraryOutput);
  const arbitrarySentinel = join(arbitraryOutput, 'keep.txt');
  await writeFile(arbitrarySentinel, 'keep arbitrary data\n');
  const arbitraryResult = runBuild(source, arbitraryOutput);
  assert.notEqual(arbitraryResult.status, 0, failureText(arbitraryResult));
  assert.match(failureText(arbitraryResult), /dedicated directory named public/);
  assert.equal(await readFile(arbitrarySentinel, 'utf8'), 'keep arbitrary data\n');

  const ancestorOutput = join(temporary, 'ancestor', 'public');
  const nestedSource = join(ancestorOutput, 'source');
  await createSource(nestedSource);
  const ancestorSentinel = join(ancestorOutput, 'keep.txt');
  await writeFile(ancestorSentinel, 'keep ancestor data\n');
  const ancestorResult = runBuild(nestedSource, ancestorOutput);
  assert.notEqual(ancestorResult.status, 0, failureText(ancestorResult));
  assert.match(failureText(ancestorResult), /must not overlap/);
  assert.equal(await readFile(ancestorSentinel, 'utf8'), 'keep ancestor data\n');

  const descendantSource = join(temporary, 'descendant-source');
  await createSource(descendantSource);
  const descendantParent = join(descendantSource, 'new-output-parent');
  const descendantResult = runBuild(descendantSource, join(descendantParent, 'public'));
  assert.notEqual(descendantResult.status, 0, failureText(descendantResult));
  assert.match(failureText(descendantResult), /must not overlap/);
  await assert.rejects(readFile(descendantParent), { code: 'ENOENT' });
});

test('frontend build removes only stale owned files and preserves unrelated files', async (t) => {
  const temporary = await mkdtemp(join(tmpdir(), 's2t-frontend-owned-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));

  const source = join(temporary, 'source');
  const output = join(temporary, 'deployment', 'public');
  await createSource(source, { 'assets/stale.txt': 'generated v1\n' });

  const firstResult = runBuild(source, output);
  assert.equal(firstResult.status, 0, failureText(firstResult));
  assert.equal(await readFile(join(output, 'assets', 'stale.txt'), 'utf8'), 'generated v1\n');

  const unrelated = join(output, 'operator-note.txt');
  await writeFile(unrelated, 'do not delete\n');
  await writeFile(join(source, 'index.html'), '<h1>index-v2</h1>\n');
  await unlink(join(source, 'assets', 'stale.txt'));

  const secondResult = runBuild(source, output);
  assert.equal(secondResult.status, 0, failureText(secondResult));
  assert.equal(await readFile(join(output, 'index.html'), 'utf8'), '<h1>index-v2</h1>\n');
  await assert.rejects(readFile(join(output, 'assets', 'stale.txt')), { code: 'ENOENT' });
  assert.equal(await readFile(unrelated, 'utf8'), 'do not delete\n');

  const manifest = JSON.parse(
    await readFile(join(dirname(output), '.public.s2t-generated-manifest.json'), 'utf8'),
  );
  assert.equal(manifest.schema, 1);
  assert.equal(manifest.files['assets/stale.txt'], undefined);
  assert.match(manifest.files['index.html'], /^[a-f0-9]{64}$/);
});

test('frontend build refuses to overwrite unowned or modified files', async (t) => {
  const temporary = await mkdtemp(join(tmpdir(), 's2t-frontend-collision-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));

  const source = join(temporary, 'source');
  const output = join(temporary, 'deployment', 'public');
  await createSource(source);
  await mkdir(output, { recursive: true });
  await writeFile(join(output, 'index.html'), 'operator-owned index\n');

  const collisionResult = runBuild(source, output);
  assert.notEqual(collisionResult.status, 0, failureText(collisionResult));
  assert.match(failureText(collisionResult), /unowned file/);
  assert.equal(await readFile(join(output, 'index.html'), 'utf8'), 'operator-owned index\n');

  await rm(output, { recursive: true });
  const firstResult = runBuild(source, output);
  assert.equal(firstResult.status, 0, failureText(firstResult));
  await writeFile(join(output, 'index.html'), 'operator edit after generation\n');
  await writeFile(join(source, 'index.html'), '<h1>index-v2</h1>\n');

  const modifiedResult = runBuild(source, output);
  assert.notEqual(modifiedResult.status, 0, failureText(modifiedResult));
  assert.match(failureText(modifiedResult), /was modified/);
  assert.equal(await readFile(join(output, 'index.html'), 'utf8'), 'operator edit after generation\n');
});

test('legacy default public output is adopted without deleting unrelated files', async (t) => {
  const temporary = await mkdtemp(join(tmpdir(), 's2t-frontend-legacy-'));
  t.after(() => rm(temporary, { recursive: true, force: true }));

  const frontend = join(temporary, 'frontend');
  const source = join(frontend, 'source');
  const output = join(frontend, 'public');
  await mkdir(frontend, { recursive: true });
  await copyFile(buildScript, join(frontend, 'build.mjs'));
  await createSource(source);
  await mkdir(output);
  await writeFile(join(output, 'index.html'), 'legacy generated index\n');
  await writeFile(join(output, 'unrelated.txt'), 'preserve me\n');

  const result = spawnSync(process.execPath, [join(frontend, 'build.mjs')], {
    cwd: frontend,
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, failureText(result));
  assert.equal(await readFile(join(output, 'index.html'), 'utf8'), '<h1>index-v1</h1>\n');
  assert.equal(await readFile(join(output, 'unrelated.txt'), 'utf8'), 'preserve me\n');
  assert.equal(
    JSON.parse(await readFile(join(frontend, '.vercel', 's2t-generated-public-manifest.json'))).schema,
    1,
  );

  const relocatedFrontend = join(temporary, 'relocated-frontend');
  await cp(frontend, relocatedFrontend, { recursive: true });
  const relocatedResult = spawnSync(process.execPath, [join(relocatedFrontend, 'build.mjs')], {
    cwd: relocatedFrontend,
    encoding: 'utf8',
  });
  assert.equal(relocatedResult.status, 0, failureText(relocatedResult));
  assert.equal(
    await readFile(join(relocatedFrontend, 'public', 'unrelated.txt'), 'utf8'),
    'preserve me\n',
  );
});
