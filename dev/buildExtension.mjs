// Assembles the Chrome MV3 extension from the production build in `dist`
import {
  cpSync, readFileSync, rmSync, writeFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const DIST_DIR = join(ROOT, 'dist');
const EXTENSION_SOURCE_DIR = join(ROOT, 'extension');
const OUTPUT_DIR = join(ROOT, 'dist-extension');
const SOURCE_MAP_SUFFIX = '.map';

rmSync(OUTPUT_DIR, { recursive: true, force: true });
cpSync(DIST_DIR, OUTPUT_DIR, { recursive: true, filter: (path) => !path.endsWith(SOURCE_MAP_SUFFIX) });
cpSync(EXTENSION_SOURCE_DIR, OUTPUT_DIR, { recursive: true });

const { version } = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8'));
const manifestPath = join(OUTPUT_DIR, 'manifest.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
manifest.version = version;
writeFileSync(manifestPath, `${JSON.stringify(manifest, undefined, 2)}\n`);

// eslint-disable-next-line no-console
console.log(`Liquidgram extension ${version} is ready in ${OUTPUT_DIR}`);
