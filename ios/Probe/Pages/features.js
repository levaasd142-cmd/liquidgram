// Feature checks of the transport probe. The app loads this page over the custom scheme and over the loopback
// server; each check posts `{ type: 'check', name, ok, detail }` to the `probe` message handler and the page ends
// with `{ type: 'done' }`. Names without the `info-` prefix are capabilities Telegram Web A needs.
import { depValue } from './module-dep.js';

const params = new URLSearchParams(window.location.search);
const PHASE = params.get('phase') || 'main';
const RUN_ID = params.get('run') || 'local';
const TELEGRAM_WEBSOCKET_URL = 'wss://venus.web.telegram.org/apiws';
const CHECK_TIMEOUT_MS = 30000;
const MEDIA_EVENT_TIMEOUT_MS = 15000;
const PLAYBACK_TIMEOUT_MS = 12000;
const MAX_SEEK_ERROR_SECONDS = 1.5;
const MIN_PROGRESS_SECONDS = 0.3;
const DOWNLOAD_TIMEOUT_MS = 20000;
const MARKER_KEY = 'probe-marker';
const DB_NAME = 'probe-db';
const STORE_NAME = 'kv';
const CACHE_NAME = 'probe-cache';
// The web app keys Cache Storage entries under this base on origins that are not http(s), see `src/util/cacheApi.ts`
const CACHE_KEY = 'https://liquidgram.invalid/probe-marker';

const post = window.__probePost || ((message) => console.log('[probe]', JSON.stringify(message)));
const list = document.getElementById('list');
const stage = document.getElementById('stage');
let buildInfo = {};
let passed = 0;
let failed = 0;

void main();

async function main() {
  document.getElementById('title').textContent = `Transport probe: ${window.location.origin} (${PHASE})`;
  try {
    buildInfo = await (await fetch('build-info.json', { cache: 'no-store' })).json();
  } catch (err) {
    report('build-info', false, err);
  }

  if (PHASE === 'verify') {
    await runVerifyChecks();
  } else if (PHASE === 'cleared') {
    await runClearedChecks();
  } else {
    await runMainChecks();
  }
  post({
    type: 'done', phase: PHASE, passed, failed,
  });
}

async function runMainChecks() {
  await check('origin', checkOrigin);
  await check('injected-scripts', checkInjectedScripts);
  await check('secure-context', checkSecureContext);
  await check('crypto-subtle', checkCryptoSubtle);
  await check('crypto-random-uuid', checkRandomUuid);
  await check('getusermedia-exists', checkGetUserMediaExists);
  await check('local-storage-write', writeLocalStorage);
  await check('indexeddb-write', writeIndexedDb);
  await check('cache-storage-write', writeCacheStorage);
  await check('storage-persist', checkStoragePersist);
  await check('web-locks', checkWebLocks);
  await check('classic-script', checkClassicScript);
  await check('module-script', checkModuleScript);
  await check('dynamic-import', checkDynamicImport);
  await check('fetch-json', checkFetchJson);
  await check('fetch-head', checkFetchHead);
  await check('fetch-404', checkFetch404);
  await check('fetch-range', checkFetchRange);
  await check('fetch-traversal', checkFetchTraversal);
  await check('xhr', checkXhr);
  await check('wasm-streaming', checkWasmStreaming);
  await check('wasm-instantiate', checkWasmInstantiate);
  await check('image-load', checkImageLoad);
  await check('font-load', checkFontLoad);
  await check('worker-classic', checkClassicWorker);
  await check('worker-module', checkModuleWorker);
  await check('worker-websocket', checkWorkerWebSocket);
  await check('sharedworker-load', () => askSharedWorker('shared-basic.js', undefined, 'ping', 'pong'));
  await check('sharedworker-module-load', () => askSharedWorker('shared-module-basic.js', 'module', 'ping', 'pong'));
  await check('info-sharedworker-importscripts', () => (
    askSharedWorker('shared-basic.js', undefined, 'importScripts', 'helper-ok')
  ));
  await check('info-sharedworker-fetch', () => askSharedWorker('shared-basic.js', undefined, 'fetch', '200 data-ok'));
  await check('info-sharedworker-subtle', () => askSharedWorker('shared-basic.js', undefined, 'subtle', 'SHA-256 ok'));
  await check('info-sharedworker-module-import', () => askSharedWorker('shared-module.js', 'module', 'ping', 'dep-ok'));
  await check('broadcast-channel', checkBroadcastChannel);
  await check('compression-streams', checkCompressionStreams);
  await check('blob-url', checkBlobUrl);
  await check('blob-download', checkBlobDownload);
  await check('audio-bundle', checkBundledAudio);
  await check('audio-seek', checkAudioSeek);
  await check('video-seek', checkVideoSeek);
  await check('video-bundle', checkBundledVideo);
  await check('video-blob', checkBlobVideo);
  await check('websocket-telegram', checkPageWebSocket);
  await check('history-api', checkHistoryApi);
  await check('info-cross-origin-fetch', checkCrossOriginFetch);
  await check('info-request-headers', checkRequestHeaders);
  await check('info-cookie', checkCookie);
  await check('info-apis', checkApiPresence);
}

async function runVerifyChecks() {
  await check('origin', checkOrigin);
  await check('secure-context', checkSecureContext);
  await check('persist-local-storage', verifyLocalStorage);
  await check('persist-indexeddb', verifyIndexedDb);
  await check('persist-cache-storage', verifyCacheStorage);
  await check('info-storage-persisted', checkStoragePersisted);
}

// After the app removed all website data the way `TestHooks.prepareForLaunch` does for a clean start
async function runClearedChecks() {
  await check('clean-start-local-storage', () => expectCleared(() => localStorage.getItem(MARKER_KEY)));
  await check('clean-start-indexeddb', () => expectCleared(readIndexedDbMarker));
  await check('clean-start-cache-storage', () => expectCleared(readCacheStorageMarker));
}

async function expectCleared(read) {
  const value = await read();
  assert(value === undefined || value === null, `still found ${describe(value)}`);
  return 'removed';
}

async function check(name, run) {
  try {
    const detail = await withTimeout(Promise.resolve().then(run), CHECK_TIMEOUT_MS, name);
    report(name, true, detail);
  } catch (err) {
    report(name, false, err);
  }
}

function report(name, ok, detail) {
  const text = describe(detail === undefined ? '' : detail).slice(0, 4000);
  if (ok) {
    passed += 1;
  } else {
    failed += 1;
  }
  post({
    type: 'check', name, ok: Boolean(ok), detail: text,
  });
  const item = document.createElement('li');
  item.className = ok ? 'ok' : 'fail';
  item.textContent = `${ok ? 'PASS' : 'FAIL'} ${name}: ${text.slice(0, 160)}`;
  list.appendChild(item);
}

function describe(value) {
  if (value instanceof Error) return `${value.name}: ${value.message}`;
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value);
  } catch (err) {
    return String(value);
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function withTimeout(promise, timeoutMs, label) {
  let timer;
  const timeout = new Promise((resolve, reject) => {
    timer = setTimeout(() => reject(new Error(`timeout after ${timeoutMs} ms (${label})`)), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function toHex(buffer) {
  return Array.from(new Uint8Array(buffer), (byte) => byte.toString(16).padStart(2, '0')).join('');
}

function checkOrigin() {
  assert(window.location.origin !== 'null', 'opaque origin');
  return {
    origin: window.location.origin, selfOrigin: self.origin, href: window.location.href, protocol: window.location.protocol,
  };
}

function checkInjectedScripts() {
  assert(window.__probeInjected === true, 'the probe user script did not run');
  assert(window.__liquidgramNative && window.__liquidgramNative.isBridgeInstalled, 'bridge.js did not run');
  return 'user scripts ran at document start';
}

function checkSecureContext() {
  assert(window.isSecureContext === true, `isSecureContext is ${window.isSecureContext}`);
  return 'isSecureContext is true';
}

async function checkCryptoSubtle() {
  assert(crypto.subtle, 'crypto.subtle is missing');
  const encoder = new TextEncoder();
  const sha256 = toHex(await crypto.subtle.digest('SHA-256', encoder.encode('abc')));
  assert(sha256 === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', `SHA-256 ${sha256}`);
  const sha1 = toHex(await crypto.subtle.digest('SHA-1', encoder.encode('abc')));
  assert(sha1 === 'a9993e364706816aba3e25717850c26c9cd0d89d', `SHA-1 ${sha1}`);

  const aesKey = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, aesKey, encoder.encode('probe'));
  const plain = new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, aesKey, cipher));
  assert(plain === 'probe', 'AES-GCM round trip failed');

  const hmacKey = await crypto.subtle.importKey(
    'raw', encoder.encode('key'), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const mac = toHex(await crypto.subtle.sign('HMAC', hmacKey, encoder.encode('The quick brown fox jumps over the lazy dog')));
  assert(mac === 'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8', `HMAC ${mac}`);

  // Telegram's two-step verification derives keys with PBKDF2-HMAC-SHA512
  const passwordKey = await crypto.subtle.importKey('raw', encoder.encode('password'), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2', hash: 'SHA-512', salt: encoder.encode('salt'), iterations: 1000,
    },
    passwordKey,
    512,
  );
  assert(bits.byteLength === 64, 'PBKDF2 failed');
  return 'SHA-1, SHA-256, AES-GCM, HMAC and PBKDF2 work';
}

function checkRandomUuid() {
  assert(typeof crypto.randomUUID === 'function', 'crypto.randomUUID is missing');
  const uuid = crypto.randomUUID();
  assert(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(uuid), uuid);
  return uuid;
}

// Only checks that the API exists in this context and lists the devices: the probe records no audio or video
async function checkGetUserMediaExists() {
  const { mediaDevices } = navigator;
  assert(mediaDevices && typeof mediaDevices.getUserMedia === 'function', `navigator.mediaDevices is ${typeof mediaDevices}`);
  const devices = await mediaDevices.enumerateDevices();
  return {
    getUserMedia: typeof mediaDevices.getUserMedia,
    devices: devices.map((device) => device.kind).join(',') || 'none',
    MediaRecorder: typeof window.MediaRecorder,
    AudioContext: typeof (window.AudioContext || window.webkitAudioContext),
    RTCPeerConnection: typeof window.RTCPeerConnection,
  };
}

function writeLocalStorage() {
  localStorage.setItem(MARKER_KEY, RUN_ID);
  assert(localStorage.getItem(MARKER_KEY) === RUN_ID, 'read back failed');
  return `stored ${RUN_ID}`;
}

function verifyLocalStorage() {
  const value = localStorage.getItem(MARKER_KEY);
  assert(value === RUN_ID, `found ${value} instead of ${RUN_ID}`);
  return `found ${value}`;
}

function openProbeDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore(STORE_NAME);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error('open failed'));
    request.onblocked = () => reject(new Error('open blocked'));
  });
}

function settleRequest(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error('request failed'));
  });
}

function settleTransaction(transaction) {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error || new Error('transaction failed'));
    transaction.onabort = () => reject(transaction.error || new Error('transaction aborted'));
  });
}

async function writeIndexedDb() {
  const db = await openProbeDb();
  try {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    transaction.objectStore(STORE_NAME).put({ runId: RUN_ID, bytes: new Uint8Array([1, 2, 3]).buffer }, MARKER_KEY);
    await settleTransaction(transaction);
    const value = await settleRequest(db.transaction(STORE_NAME).objectStore(STORE_NAME).get(MARKER_KEY));
    assert(value && value.runId === RUN_ID && value.bytes.byteLength === 3, 'read back failed');
  } finally {
    db.close();
  }
  return `stored ${RUN_ID}`;
}

async function readIndexedDbMarker() {
  const db = await openProbeDb();
  try {
    const value = await settleRequest(db.transaction(STORE_NAME).objectStore(STORE_NAME).get(MARKER_KEY));
    return value ? value.runId : undefined;
  } finally {
    db.close();
  }
}

async function verifyIndexedDb() {
  const value = await readIndexedDbMarker();
  assert(value === RUN_ID, `found ${value} instead of ${RUN_ID}`);
  return `found ${value}`;
}

async function writeCacheStorage() {
  assert(self.caches, 'caches is missing');
  const cache = await caches.open(CACHE_NAME);
  await cache.put(CACHE_KEY, new Response(RUN_ID, { headers: { 'Content-Type': 'text/plain' } }));
  const match = await cache.match(CACHE_KEY);
  assert(match && await match.text() === RUN_ID, 'match failed');
  return `stored ${RUN_ID} under ${CACHE_KEY}`;
}

async function readCacheStorageMarker() {
  assert(self.caches, 'caches is missing');
  const cache = await caches.open(CACHE_NAME);
  const match = await cache.match(CACHE_KEY);
  return match ? match.text() : undefined;
}

async function verifyCacheStorage() {
  const value = await readCacheStorageMarker();
  assert(value === RUN_ID, `found ${value} instead of ${RUN_ID}`);
  return `found ${value}`;
}

async function checkStoragePersist() {
  const { storage } = navigator;
  assert(storage && typeof storage.persist === 'function', `navigator.storage is ${typeof storage}`);
  const isPersistent = await storage.persist();
  const isPersisted = typeof storage.persisted === 'function' ? await storage.persisted() : 'n/a';
  const estimate = typeof storage.estimate === 'function' ? await storage.estimate() : {};
  return {
    persist: isPersistent, persisted: isPersisted, quota: estimate.quota, usage: estimate.usage,
  };
}

async function checkStoragePersisted() {
  const { storage } = navigator;
  assert(storage && typeof storage.persisted === 'function', `navigator.storage is ${typeof storage}`);
  return { persisted: await storage.persisted() };
}

async function checkWebLocks() {
  assert(navigator.locks && typeof navigator.locks.request === 'function', 'navigator.locks is missing');
  const value = await navigator.locks.request('probe-lock', async () => 42);
  assert(value === 42, `lock callback returned ${value}`);
  return 'lock granted';
}

function checkClassicScript() {
  assert(window.__probeClassic === 'classic-ok', `classic script value ${window.__probeClassic}`);
  return 'classic-ok';
}

function checkModuleScript() {
  assert(depValue === 'dep-ok', `static import value ${depValue}`);
  assert(import.meta.url.startsWith(window.location.origin), `import.meta.url ${import.meta.url}`);
  return import.meta.url;
}

async function checkDynamicImport() {
  const module = await import('./module-dyn.js');
  assert(module.dynValue === 'dyn-ok', `dynamic import value ${module.dynValue}`);
  return 'dyn-ok';
}

async function checkFetchJson() {
  const response = await fetch('data.json', { cache: 'no-store' });
  assert(response.status === 200, `status ${response.status}`);
  const data = await response.json();
  assert(data.probe === 'data-ok' && data.unicode === 'Привет ✓', 'wrong data');
  return {
    status: response.status,
    type: response.headers.get('content-type'),
    cacheControl: response.headers.get('cache-control'),
    length: response.headers.get('content-length'),
  };
}

async function checkFetchHead() {
  const response = await fetch('/index.html', { method: 'HEAD', cache: 'no-store' });
  const body = await response.arrayBuffer();
  const length = Number(response.headers.get('content-length'));
  assert(response.status === 200, `status ${response.status}`);
  assert(length > 0, `content-length ${length}`);
  assert(body.byteLength === 0, `body of ${body.byteLength} bytes`);
  return { status: response.status, length, type: response.headers.get('content-type') };
}

async function checkFetch404() {
  const response = await fetch('/__probe/missing-file.txt', { cache: 'no-store' });
  assert(response.status === 404, `status ${response.status}`);
  return 'status 404';
}

async function getLength(url) {
  const response = await fetch(url, { method: 'HEAD', cache: 'no-store' });
  return Number(response.headers.get('content-length'));
}

async function checkFetchRange() {
  const url = '/__probe/probe-video.mp4';
  const size = await getLength(url);
  assert(size > 1000, `size ${size}`);
  const results = [];

  async function expectRange(range, status, length, contentRange) {
    const response = await fetch(url, { headers: { Range: range }, cache: 'no-store' });
    const body = await response.arrayBuffer();
    const actualRange = response.headers.get('content-range');
    results.push(`${range} -> ${response.status} ${body.byteLength} [${actualRange}]`);
    assert(response.status === status, `${range}: status ${response.status}`);
    if (length !== undefined) assert(body.byteLength === length, `${range}: ${body.byteLength} bytes`);
    assert(actualRange === contentRange, `${range}: content-range ${actualRange}`);
    return new Uint8Array(body);
  }

  const middle = await expectRange('bytes=100-199', 206, 100, `bytes 100-199/${size}`);
  await expectRange('bytes=0-1', 206, 2, `bytes 0-1/${size}`);
  await expectRange('bytes=-100', 206, 100, `bytes ${size - 100}-${size - 1}/${size}`);
  await expectRange(`bytes=${size - 10}-`, 206, 10, `bytes ${size - 10}-${size - 1}/${size}`);
  await expectRange(`bytes=${size}-`, 416, undefined, `bytes */${size}`);

  const full = new Uint8Array(await (await fetch(url, { cache: 'no-store' })).arrayBuffer());
  assert(full.length === size, `full body of ${full.length} bytes`);
  assert(middle.every((byte, index) => byte === full[100 + index]), 'range bytes differ from the file');
  return results.join('; ');
}

// Paths that try to leave the web build. WebKit normalizes plain dot segments, so the escapes reach the server.
async function checkFetchTraversal() {
  const attempts = [
    '/..%2FInfo.plist',
    '/assets%2F..%2F..%2FInfo.plist',
    '/__probe/..%2F..%2FInfo.plist',
    '/%2e%2e/Info.plist',
    '/%5c..%5cInfo.plist',
    '/index.html%00.png',
  ];
  const results = [];
  for (const path of attempts) {
    let status;
    let hasLeaked = false;
    try {
      const response = await fetch(path, { cache: 'no-store' });
      status = response.status;
      const head = String.fromCharCode(...new Uint8Array(await response.arrayBuffer()).slice(0, 8));
      hasLeaked = head.startsWith('bplist') || head.startsWith('<?xml');
    } catch (err) {
      status = `rejected (${err.message})`;
    }
    results.push(`${path} -> ${status}`);
    assert(status !== 200 && !hasLeaked, `${path} answered ${status}`);
  }
  return results.join('; ');
}

function sendXhr(url, responseType) {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    request.open('GET', url);
    request.responseType = responseType;
    request.onload = () => resolve(request);
    request.onerror = () => reject(new Error(`XHR error, status ${request.status}`));
    request.send();
  });
}

async function checkXhr() {
  const wasmUrl = (buildInfo.wasm || [])[0];
  assert(wasmUrl, 'no .wasm file in the build');
  const size = await getLength(wasmUrl);
  const binary = await sendXhr(wasmUrl, 'arraybuffer');
  assert(binary.status === 200, `status ${binary.status}`);
  assert(binary.response && binary.response.byteLength === size, `${binary.response && binary.response.byteLength} of ${size} bytes`);
  const json = await sendXhr('data.json', 'json');
  assert(json.status === 200 && json.response && json.response.probe === 'data-ok', 'JSON XHR failed');
  return { url: wasmUrl, bytes: size, type: binary.getResponseHeader('content-type') };
}

async function checkWasmStreaming() {
  const wasm = buildInfo.wasm || [];
  const url = wasm.find((name) => name.includes('tlottie')) || wasm[0];
  assert(url, 'no .wasm file in the build');
  const module = await WebAssembly.compileStreaming(fetch(url));
  return `${url}: ${WebAssembly.Module.exports(module).length} exports, ${WebAssembly.Module.imports(module).length} imports`;
}

async function checkWasmInstantiate() {
  // (module (func (export "add") (param i32 i32) (result i32) local.get 0 local.get 1 i32.add))
  const bytes = new Uint8Array([
    0, 97, 115, 109, 1, 0, 0, 0, 1, 7, 1, 96, 2, 127, 127, 1, 127, 3, 2, 1, 0, 7, 7, 1, 3, 97, 100, 100, 0, 0,
    10, 9, 1, 7, 0, 32, 0, 32, 1, 106, 11,
  ]);
  const { instance } = await WebAssembly.instantiate(bytes);
  assert(instance.exports.add(2, 3) === 5, 'add(2, 3) failed');
  return 'add(2, 3) = 5';
}

async function checkImageLoad() {
  const image = new Image();
  image.src = '/icon-192x192.png';
  await image.decode();
  assert(image.naturalWidth === 192, `width ${image.naturalWidth}`);
  return '192x192';
}

async function checkFontLoad() {
  const url = (buildInfo.fonts || [])[0];
  assert(url, 'no .woff2 file in the build');
  const face = new FontFace('ProbeFont', `url(${url})`);
  await face.load();
  return `${url} ${face.status}`;
}

function runDedicatedWorker(url, options, message) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(url, options);
    const timer = setTimeout(() => {
      worker.terminate();
      reject(new Error('no answer from the worker'));
    }, CHECK_TIMEOUT_MS - 1000);
    worker.onmessage = (e) => {
      clearTimeout(timer);
      worker.terminate();
      resolve(e.data);
    };
    worker.onerror = (e) => {
      clearTimeout(timer);
      worker.terminate();
      reject(new Error(`worker error: ${e.message || 'the script did not load'}`));
    };
    worker.postMessage(message);
  });
}

// Starts a new instance of a shared worker, sends it a task and expects `value` in its answer
function askSharedWorker(url, type, task, value) {
  assert(typeof SharedWorker === 'function', 'SharedWorker is missing');
  return new Promise((resolve, reject) => {
    const worker = new SharedWorker(url, { name: `probe-${task}-${Math.random()}`, type });
    const timer = setTimeout(() => reject(new Error('no answer from the shared worker')), CHECK_TIMEOUT_MS - 1000);
    worker.onerror = (e) => {
      clearTimeout(timer);
      reject(new Error(`shared worker error: ${e.message || 'the script did not load'}`));
    };
    worker.port.onmessage = ({ data }) => {
      clearTimeout(timer);
      worker.port.close();
      if (data.error) {
        reject(new Error(data.error));
      } else if (data.value !== value) {
        reject(new Error(`answered ${describe(data.value)}`));
      } else if (data.origin !== window.location.origin || !data.isSecureContext) {
        reject(new Error(`runs in ${data.origin}, secure context ${data.isSecureContext}`));
      } else {
        resolve(`${task}: ${data.value}`);
      }
    };
    worker.port.postMessage({ task });
  });
}

function expectWorkerResult(data, expected) {
  assert(data && data.result, `unexpected answer ${describe(data)}`);
  assert(data.errors.length === 0, data.errors.join('; '));
  Object.entries(expected).forEach(([key, value]) => {
    assert(data.result[key] === value, `${key} is ${describe(data.result[key])}`);
  });
  return data.result;
}

async function checkClassicWorker() {
  const data = await runDedicatedWorker('worker-classic.js', undefined, { task: 'basic' });
  return expectWorkerResult(data, { importScripts: 'helper-ok', isSecureContext: true, origin: window.location.origin });
}

async function checkModuleWorker() {
  const wasm = buildInfo.wasm || [];
  const wasmUrl = wasm.find((name) => name.includes('tlottie')) || wasm[0];
  const data = await runDedicatedWorker('worker-module.js', { type: 'module' }, { wasmUrl });
  return expectWorkerResult(data, {
    staticImport: 'dep-ok', dynamicImport: 'dyn-ok', isSecureContext: true, origin: window.location.origin,
  });
}

async function checkWorkerWebSocket() {
  const data = await runDedicatedWorker('worker-classic.js', undefined, { task: 'websocket', url: TELEGRAM_WEBSOCKET_URL });
  return expectWorkerResult(data, {}).websocket;
}

async function checkBroadcastChannel() {
  const name = `probe-channel-${Math.random()}`;
  const sender = new BroadcastChannel(name);
  const receiver = new BroadcastChannel(name);
  const pageMessage = new Promise((resolve) => {
    receiver.onmessage = (e) => resolve(e.data);
  });
  sender.postMessage({ from: 'page' });
  const pageData = await withTimeout(pageMessage, 5000, 'page to page');
  sender.close();
  receiver.close();
  assert(pageData.from === 'page', 'wrong page message');

  const workerChannel = new BroadcastChannel('probe-worker-channel');
  const workerMessage = new Promise((resolve) => {
    workerChannel.onmessage = (e) => resolve(e.data);
  });
  await runDedicatedWorker('worker-classic.js', undefined, { task: 'broadcast' });
  const workerData = await withTimeout(workerMessage, 5000, 'worker to page');
  workerChannel.close();
  assert(workerData === 'from-worker', `wrong worker message ${describe(workerData)}`);
  return 'page to page and worker to page delivered';
}

async function roundTrip(input, format) {
  const compressed = await new Response(new Blob([input]).stream().pipeThrough(new CompressionStream(format)))
    .arrayBuffer();
  const restored = new Uint8Array(
    await new Response(new Blob([compressed]).stream().pipeThrough(new DecompressionStream(format))).arrayBuffer(),
  );
  assert(restored.length === input.length && restored.every((byte, index) => byte === input[index]), `${format} differs`);
  return `${format} ${input.length} -> ${compressed.byteLength}`;
}

async function checkCompressionStreams() {
  assert(typeof CompressionStream === 'function' && typeof DecompressionStream === 'function', 'streams are missing');
  const input = new TextEncoder().encode('liquidgram '.repeat(300));
  const results = [await roundTrip(input, 'gzip'), await roundTrip(input, 'deflate')];
  try {
    results.push(await roundTrip(input, 'deflate-raw'));
  } catch (err) {
    results.push(`deflate-raw unsupported (${err.message})`);
  }
  return results.join('; ');
}

// Runs a step and names it in the error, so a failure says which part of a check broke
async function step(label, run) {
  try {
    return await run();
  } catch (err) {
    throw new Error(`${label}: ${describe(err)}`);
  }
}

async function checkBlobUrl() {
  const textUrl = await step('create a text URL', () => URL.createObjectURL(new Blob(['blob-ok'], { type: 'text/plain' })));
  assert(textUrl.startsWith(`blob:${window.location.origin}/`), textUrl);
  const text = await step('fetch the text URL', async () => (await fetch(textUrl)).text());
  URL.revokeObjectURL(textUrl);
  assert(text === 'blob-ok', `fetched ${text}`);

  const png = await step('read an image', async () => (await fetch('/icon-192x192.png')).blob());
  const imageUrl = await step('create an image URL', () => URL.createObjectURL(png));
  const image = new Image();
  image.src = imageUrl;
  await step('decode the image URL', () => image.decode());
  URL.revokeObjectURL(imageUrl);
  assert(image.naturalWidth === 192, `image width ${image.naturalWidth}`);

  const canvas = document.createElement('canvas');
  canvas.width = 8;
  canvas.height = 8;
  canvas.getContext('2d').fillRect(0, 0, 8, 8);
  const canvasBlob = await step('encode a canvas', () => new Promise((resolve) => {
    canvas.toBlob(resolve, 'image/png');
  }));
  return { url: textUrl, image: `${image.naturalWidth}x${image.naturalHeight}`, canvasBlob: canvasBlob ? canvasBlob.size : 'null' };
}

// The app saves the file natively and calls `window.__probeDownloadDone(name, size)`
async function checkBlobDownload() {
  const content = 'liquidgram download probe';
  const url = URL.createObjectURL(new Blob([content], { type: 'text/plain' }));
  const done = new Promise((resolve) => {
    window.__probeDownloadDone = (name, size) => resolve({ name, size });
  });
  const link = document.createElement('a');
  link.href = url;
  link.download = 'probe-download.txt';
  document.body.appendChild(link);
  link.click();
  link.remove();
  try {
    const result = await withTimeout(done, DOWNLOAD_TIMEOUT_MS, 'download');
    assert(result.size === content.length, `saved ${result.size} bytes`);
    return result;
  } finally {
    URL.revokeObjectURL(url);
  }
}

function waitForMediaEvent(media, name) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`no ${name} (readyState ${media.readyState}, networkState ${media.networkState})`));
    }, MEDIA_EVENT_TIMEOUT_MS);
    function onEvent() {
      cleanup();
      resolve();
    }
    function onError() {
      cleanup();
      reject(new Error(`media error ${media.error ? `${media.error.code} ${media.error.message}` : 'unknown'}`));
    }
    function cleanup() {
      clearTimeout(timer);
      media.removeEventListener(name, onEvent);
      media.removeEventListener('error', onError);
    }
    media.addEventListener(name, onEvent);
    media.addEventListener('error', onError);
  });
}

function waitForCondition(condition, label) {
  return new Promise((resolve, reject) => {
    const startedAt = Date.now();
    (function poll() {
      if (condition()) {
        resolve();
        return;
      }
      if (Date.now() - startedAt > PLAYBACK_TIMEOUT_MS) {
        reject(new Error(`timeout waiting for ${label()}`));
        return;
      }
      setTimeout(poll, 100);
    }());
  });
}

// Plays muted media from `src`, seeks to `seekFraction` of its duration and checks that playback continues there,
// which needs range requests into the middle of the file
async function playAndSeek(media, src, seekFraction) {
  const events = [];
  ['loadedmetadata', 'canplay', 'playing', 'seeking', 'seeked', 'waiting', 'stalled'].forEach((name) => {
    media.addEventListener(name, () => events.push(`${name}@${media.currentTime.toFixed(1)}`));
  });
  media.muted = true;
  media.preload = 'auto';
  media.setAttribute('playsinline', '');
  const metadata = waitForMediaEvent(media, 'loadedmetadata');
  media.src = src;
  try {
    await metadata;
    assert(Number.isFinite(media.duration) && media.duration > 0, `duration ${media.duration}`);
    await media.play();
    await waitForCondition(() => media.currentTime > MIN_PROGRESS_SECONDS, () => `playback (at ${media.currentTime})`);
    const result = { duration: Number(media.duration.toFixed(2)) };
    if (seekFraction) {
      const target = media.duration * seekFraction;
      const seeked = waitForMediaEvent(media, 'seeked');
      media.currentTime = target;
      await seeked;
      assert(Math.abs(media.currentTime - target) < MAX_SEEK_ERROR_SECONDS, `seeked to ${media.currentTime}, not ${target}`);
      const seekedTo = media.currentTime;
      await waitForCondition(
        () => media.currentTime > seekedTo + MIN_PROGRESS_SECONDS,
        () => `playback after the seek (at ${media.currentTime})`,
      );
      result.seekedTo = Number(seekedTo.toFixed(2));
      result.playedTo = Number(media.currentTime.toFixed(2));
    }
    if (media.videoWidth !== undefined) {
      result.size = `${media.videoWidth}x${media.videoHeight}`;
    }
    return result;
  } catch (err) {
    err.message = `${err.message}; events: ${events.join(' ')}`;
    throw err;
  } finally {
    media.pause();
    showMediaEvents(events);
  }
}

// Keeps the event log of each media check visible on the page
function showMediaEvents(events) {
  const item = document.createElement('div');
  item.textContent = events.join(' ');
  stage.appendChild(item);
}

function createVideo() {
  const video = document.createElement('video');
  stage.appendChild(video);
  return video;
}

function checkBundledAudio() {
  return playAndSeek(new Audio(), '/call_busy.mp3', 0);
}

function checkAudioSeek() {
  return playAndSeek(new Audio(), '/__probe/probe-audio.m4a', 0.6);
}

function checkVideoSeek() {
  return playAndSeek(createVideo(), '/__probe/probe-video.mp4', 0.6);
}

function checkBundledVideo() {
  return playAndSeek(createVideo(), '/nojs.mp4', 0);
}

// Telegram Web A plays downloaded media from `blob:` URLs
async function checkBlobVideo() {
  const blob = await (await fetch('/__probe/probe-video.mp4')).blob();
  const url = URL.createObjectURL(blob);
  try {
    return await playAndSeek(createVideo(), url, 0.6);
  } finally {
    URL.revokeObjectURL(url);
  }
}

// Opens a WebSocket to Telegram and closes it without sending anything
function checkPageWebSocket() {
  return window.__probeWorkerChecks.openAndCloseWebSocket(TELEGRAM_WEBSOCKET_URL);
}

function checkHistoryApi() {
  const original = window.location.href;
  window.history.pushState({ probe: true }, '', '#probe-hash');
  assert(window.location.hash === '#probe-hash', `after pushState ${window.location.href}`);
  window.history.replaceState(undefined, '', `${window.location.pathname}${window.location.search}#replaced`);
  assert(window.location.hash === '#replaced', `after replaceState ${window.location.href}`);
  window.history.replaceState(undefined, '', original);
  return 'pushState and replaceState work';
}

// Another origin of the same scheme, or another host name of the loopback server, must not be readable
async function checkCrossOriginFetch() {
  const isCustom = window.location.protocol !== 'http:';
  const url = isCustom ? `${window.location.protocol}//other/index.html` : `http://localhost:${window.location.port}/index.html`;
  try {
    const response = await fetch(url, { cache: 'no-store' });
    return `${url} answered ${response.status}`;
  } catch (err) {
    return `${url} rejected: ${err.message}`;
  }
}

// Headers that an HTTPS server receives from this origin: `Origin` and `Referer`
async function checkRequestHeaders() {
  const response = await fetch('https://httpbin.org/get', { cache: 'no-store' });
  const data = await response.json();
  return {
    status: response.status, origin: data.headers.Origin || '(none)', referer: data.headers.Referer || '(none)',
  };
}

function checkCookie() {
  document.cookie = 'probe=1; path=/';
  return { cookie: document.cookie, cookieEnabled: navigator.cookieEnabled };
}

function checkApiPresence() {
  return {
    serviceWorker: 'serviceWorker' in navigator,
    sharedWorker: typeof SharedWorker,
    notification: typeof window.Notification,
    clipboard: typeof (navigator.clipboard && navigator.clipboard.writeText),
    share: typeof navigator.share,
    wakeLock: typeof navigator.wakeLock,
    offscreenCanvas: typeof window.OffscreenCanvas,
    userAgent: navigator.userAgent,
  };
}
