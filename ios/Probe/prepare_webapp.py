#!/usr/bin/env python3
"""Copies a production web build and the probe pages into ios/Probe/WebApp and lists the build files the pages need.

Usage: prepare_webapp.py <dist-dir>
"""
import json
import re
import shutil
import sys
from pathlib import Path

PROBE_DIR = Path(__file__).resolve().parent
WEBAPP_DIR = PROBE_DIR / 'WebApp'
PAGES_DIR = PROBE_DIR / 'Pages'
PROBE_PATH = '__probe'
# Worker entry files sit in the root of the build, named `[name]-[hash].js` (`worker.rolldownOptions` in vite.config.ts)
GRAMJS_WORKER_RE = re.compile(r'^worker-[\w-]+\.js$')
SHARED_STATE_WORKER_RE = re.compile(r'^sharedState\.worker-[\w-]+\.js$')
# The opus-recorder workers that `src/util/oggToWav.ts` imports with `?url`, emitted as hashed assets
DECODER_WORKER_RE = re.compile(r'^decoderWorker\.min-[\w-]+\.js$')
WAVE_WORKER_RE = re.compile(r'^waveWorker\.min-[\w-]+\.js$')
LARGE_FILE_LENGTH = 32 * 1024 * 1024


def find_first(pattern, names):
    return next((name for name in names if pattern.match(name)), None)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    dist = Path(sys.argv[1]).resolve()
    if not (dist / 'index.html').is_file():
        sys.exit(f'No web build in {dist}')

    shutil.rmtree(WEBAPP_DIR, ignore_errors=True)
    # Like ios/build-ipa.sh: no source maps and no PHP helpers
    shutil.copytree(dist, WEBAPP_DIR, ignore=shutil.ignore_patterns('*.map', '*.php'))
    shutil.copytree(PAGES_DIR, WEBAPP_DIR / PROBE_PATH)

    root_files = sorted(path.name for path in WEBAPP_DIR.iterdir() if path.is_file())
    assets = sorted(path.name for path in (WEBAPP_DIR / 'assets').iterdir() if path.is_file())
    decoder_worker = find_first(DECODER_WORKER_RE, assets)
    wave_worker = find_first(WAVE_WORKER_RE, assets)
    info = {
        'gramjsWorker': find_first(GRAMJS_WORKER_RE, root_files),
        'sharedStateWorker': find_first(SHARED_STATE_WORKER_RE, root_files),
        'decoderWorker': decoder_worker and f'/assets/{decoder_worker}',
        'waveWorker': wave_worker and f'/assets/{wave_worker}',
        'wasm': [f'/assets/{name}' for name in assets if name.endswith('.wasm')],
        'fonts': [f'/assets/{name}' for name in assets if name.endswith('.woff2')],
    }
    missing = [key for key, value in info.items() if not value]
    if missing:
        sys.exit(f'The build lacks: {", ".join(missing)}')

    (WEBAPP_DIR / PROBE_PATH / 'build-info.json').write_text(json.dumps(info, indent=2) + '\n')
    # Large enough that WebKit stops the handler's tasks while they stream, when a page aborts the fetch
    pattern = bytes(range(256))
    (WEBAPP_DIR / PROBE_PATH / 'large.bin').write_bytes(pattern * (LARGE_FILE_LENGTH // len(pattern)))
    file_count = sum(1 for path in WEBAPP_DIR.rglob('*') if path.is_file())
    print(json.dumps(info, indent=2))
    print(f'{file_count} files in {WEBAPP_DIR}')


if __name__ == '__main__':
    main()
