import { createHash, randomUUID } from 'node:crypto';
import { existsSync } from 'node:fs';
import {
  lstat,
  mkdir,
  readFile,
  readdir,
  realpath,
  rename,
  rmdir,
  unlink,
  writeFile,
} from 'node:fs/promises';
import {
  basename,
  dirname,
  isAbsolute,
  join,
  normalize,
  parse,
  relative,
  resolve,
  sep,
} from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const defaultSource = existsSync(resolve(directory, 'source'))
  ? resolve(directory, 'source')
  : resolve(directory, '../public');
const defaultOutput = resolve(directory, 'public');
const args = process.argv.slice(2);

let source = defaultSource;
let output = defaultOutput;

for (let index = 0; index < args.length; index += 1) {
  const argument = args[index];
  if (argument !== '--source' && argument !== '--output') {
    throw new Error(`Unknown argument: ${argument}`);
  }

  const value = args[index + 1];
  if (!value || value.startsWith('--')) {
    throw new Error(`${argument} requires a path`);
  }

  if (argument === '--source') {
    source = resolve(value);
  } else {
    output = resolve(value);
  }
  index += 1;
}

const digest = (data) => createHash('sha256').update(data).digest('hex');

const contains = (parent, child) => {
  const path = relative(parent, child);
  return path === '' || (!isAbsolute(path) && path !== '..' && !path.startsWith(`..${sep}`));
};

const canonicalizePlannedPath = async (path) => {
  let existingPath = path;
  const missingComponents = [];
  while (!existsSync(existingPath)) {
    const parent = dirname(existingPath);
    if (parent === existingPath) {
      throw new Error(`Cannot resolve output path: ${path}`);
    }
    missingComponents.unshift(basename(existingPath));
    existingPath = parent;
  }

  const existingInfo = await lstat(existingPath);
  if (!existingInfo.isDirectory()) {
    throw new Error(`Output parent is not a directory: ${existingPath}`);
  }
  return resolve(await realpath(existingPath), ...missingComponents);
};

const isSafeRelativePath = (path) => {
  if (!path || path.includes('\0') || isAbsolute(path) || normalize(path) !== path) {
    return false;
  }
  return !path.split(sep).some((component) => component === '' || component === '..');
};

const collectFiles = async (root, current = '', files = new Map()) => {
  const entries = await readdir(join(root, current), { withFileTypes: true });
  entries.sort((left, right) => left.name.localeCompare(right.name));

  for (const entry of entries) {
    const path = current ? join(current, entry.name) : entry.name;
    if (entry.isSymbolicLink()) {
      throw new Error(`Source contains a symbolic link: ${path}`);
    }
    if (entry.isDirectory()) {
      await collectFiles(root, path, files);
      continue;
    }
    if (!entry.isFile()) {
      throw new Error(`Source contains an unsupported file type: ${path}`);
    }

    const data = await readFile(join(root, path));
    files.set(path, { data, hash: digest(data) });
  }
  return files;
};

const atomicWrite = async (path, data) => {
  const temporaryPath = `${path}.s2t-tmp-${process.pid}-${randomUUID()}`;
  try {
    await writeFile(temporaryPath, data, { flag: 'wx' });
    await rename(temporaryPath, path);
  } finally {
    try {
      await unlink(temporaryPath);
    } catch (error) {
      if (error.code !== 'ENOENT') {
        throw error;
      }
    }
  }
};

const parseManifest = async (manifestPath, outputIdentity) => {
  if (!existsSync(manifestPath)) {
    return null;
  }

  const manifestInfo = await lstat(manifestPath);
  if (!manifestInfo.isFile() || manifestInfo.isSymbolicLink()) {
    throw new Error(`Generated-file manifest is not a regular file: ${manifestPath}`);
  }
  if (manifestInfo.size > 5 * 1024 * 1024) {
    throw new Error(`Generated-file manifest is unexpectedly large: ${manifestPath}`);
  }

  let manifest;
  try {
    manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  } catch (error) {
    throw new Error(`Cannot read generated-file manifest ${manifestPath}: ${error.message}`);
  }

  if (
    manifest?.schema !== 1
    || manifest.outputIdentity !== outputIdentity
    || !manifest.files
    || Array.isArray(manifest.files)
    || typeof manifest.files !== 'object'
  ) {
    throw new Error(`Invalid generated-file manifest: ${manifestPath}`);
  }

  const entries = Object.entries(manifest.files);
  if (entries.length > 20_000) {
    throw new Error(`Generated-file manifest contains too many entries: ${manifestPath}`);
  }

  const files = new Map();
  for (const [path, expectedHash] of entries) {
    if (!isSafeRelativePath(path) || !/^[a-f0-9]{64}$/.test(expectedHash)) {
      throw new Error(`Invalid generated-file manifest entry: ${path}`);
    }
    files.set(path, expectedHash);
  }
  return files;
};

const assertSafeOutputParents = async (canonicalOutput, path) => {
  let current = canonicalOutput;
  for (const component of path.split(sep).slice(0, -1)) {
    current = join(current, component);
    if (!existsSync(current)) {
      return;
    }
    const info = await lstat(current);
    if (!info.isDirectory() || info.isSymbolicLink()) {
      throw new Error(`Output path has an unsafe parent directory: ${current}`);
    }
  }
};

const validateOwnedFiles = async (canonicalOutput, ownedFiles) => {
  for (const [path, expectedHash] of ownedFiles) {
    const target = resolve(canonicalOutput, path);
    if (!contains(canonicalOutput, target)) {
      throw new Error(`Generated-file manifest escapes its output directory: ${path}`);
    }
    await assertSafeOutputParents(canonicalOutput, path);
    if (!existsSync(target)) {
      continue;
    }

    const targetInfo = await lstat(target);
    if (!targetInfo.isFile() || targetInfo.isSymbolicLink()) {
      throw new Error(`Previously generated path is no longer a regular file: ${target}`);
    }
    if (digest(await readFile(target)) !== expectedHash) {
      throw new Error(`Previously generated file was modified; refusing to replace it: ${target}`);
    }
  }
};

const removeEmptyParents = async (path, outputRoot) => {
  let current = dirname(path);
  while (current !== outputRoot && contains(outputRoot, current)) {
    try {
      await rmdir(current);
    } catch (error) {
      if (error.code === 'ENOENT') {
        current = dirname(current);
        continue;
      }
      if (error.code === 'ENOTEMPTY' || error.code === 'EEXIST') {
        return;
      }
      throw error;
    }
    current = dirname(current);
  }
};

if (output === parse(output).root || basename(output) !== 'public') {
  throw new Error('Output must be a dedicated directory named public');
}

const sourceInfo = await lstat(source);
if (!sourceInfo.isDirectory() || sourceInfo.isSymbolicLink()) {
  throw new Error(`Source must be a regular directory: ${source}`);
}
const canonicalSource = await realpath(source);

const plannedOutputParent = await canonicalizePlannedPath(dirname(output));
const plannedOutput = resolve(plannedOutputParent, basename(output));
if (contains(canonicalSource, plannedOutput) || contains(plannedOutput, canonicalSource)) {
  throw new Error('Source and output directories must not overlap');
}

await mkdir(dirname(output), { recursive: true });
const canonicalOutputParent = await realpath(dirname(output));
if (canonicalOutputParent !== plannedOutputParent) {
  throw new Error('Output parent changed while the build was starting');
}
const outputCandidate = resolve(canonicalOutputParent, basename(output));
let canonicalOutput = outputCandidate;

if (existsSync(outputCandidate)) {
  const outputInfo = await lstat(outputCandidate);
  if (!outputInfo.isDirectory() || outputInfo.isSymbolicLink()) {
    throw new Error(`Output must be a regular directory: ${outputCandidate}`);
  }
  canonicalOutput = await realpath(outputCandidate);
}

if (canonicalOutput === parse(canonicalOutput).root || basename(canonicalOutput) !== 'public') {
  throw new Error('Canonical output must be a dedicated directory named public');
}
if (contains(canonicalSource, canonicalOutput) || contains(canonicalOutput, canonicalSource)) {
  throw new Error('Source and output directories must not overlap');
}

const canonicalDefaultOutputParent = await realpath(dirname(defaultOutput));
const canonicalDefaultOutput = resolve(canonicalDefaultOutputParent, basename(defaultOutput));
const isDefaultOutput = canonicalOutput === canonicalDefaultOutput;
const outputIdentity = isDefaultOutput
  ? 'default-public'
  : `sha256:${digest(Buffer.from(canonicalOutput))}`;
const manifestPath = isDefaultOutput
  ? join(directory, '.vercel', 's2t-generated-public-manifest.json')
  : join(canonicalOutputParent, `.${basename(canonicalOutput)}.s2t-generated-manifest.json`);
const manifestParent = dirname(manifestPath);
if (existsSync(manifestParent)) {
  const manifestParentInfo = await lstat(manifestParent);
  if (!manifestParentInfo.isDirectory() || manifestParentInfo.isSymbolicLink()) {
    throw new Error(`Generated-file manifest parent is not a regular directory: ${manifestParent}`);
  }
}
const ownedFiles = await parseManifest(manifestPath, outputIdentity);
const isLegacyDefaultOutput = isDefaultOutput && ownedFiles === null;
const previousFiles = ownedFiles ?? new Map();

await validateOwnedFiles(canonicalOutput, previousFiles);

const sourceFiles = await collectFiles(canonicalSource);
for (const requiredPath of ['index.html', join('policies', 'privacy.html')]) {
  if (!sourceFiles.has(requiredPath)) {
    throw new Error(`Missing required frontend file: ${join(canonicalSource, requiredPath)}`);
  }
}

for (const path of sourceFiles.keys()) {
  const target = resolve(canonicalOutput, path);
  if (!contains(canonicalOutput, target)) {
    throw new Error(`Source path escapes the output directory: ${path}`);
  }
  await assertSafeOutputParents(canonicalOutput, path);
  if (!existsSync(target)) {
    continue;
  }

  const targetInfo = await lstat(target);
  if (!targetInfo.isFile() || targetInfo.isSymbolicLink()) {
    throw new Error(`Output collision is not a regular file: ${target}`);
  }
  if (!previousFiles.has(path) && !isLegacyDefaultOutput) {
    throw new Error(`Output contains an unowned file; refusing to replace it: ${target}`);
  }
}

await mkdir(canonicalOutput, { recursive: true });
for (const [path, file] of sourceFiles) {
  const target = resolve(canonicalOutput, path);
  await mkdir(dirname(target), { recursive: true });
  await atomicWrite(target, file.data);
}

for (const path of previousFiles.keys()) {
  if (sourceFiles.has(path)) {
    continue;
  }
  const target = resolve(canonicalOutput, path);
  if (existsSync(target)) {
    await unlink(target);
    await removeEmptyParents(target, canonicalOutput);
  }
}

const manifest = {
  schema: 1,
  outputIdentity,
  files: Object.fromEntries(
    [...sourceFiles.entries()]
      .map(([path, file]) => [path, file.hash])
      .sort(([left], [right]) => left.localeCompare(right)),
  ),
};
await mkdir(manifestParent, { recursive: true });
const finalManifestParentInfo = await lstat(manifestParent);
if (!finalManifestParentInfo.isDirectory() || finalManifestParentInfo.isSymbolicLink()) {
  throw new Error(`Generated-file manifest parent is not a regular directory: ${manifestParent}`);
}
await atomicWrite(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

console.log(`Built billing frontend: ${canonicalOutput}`);
