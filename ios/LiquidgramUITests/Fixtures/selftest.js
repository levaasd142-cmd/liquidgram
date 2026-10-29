// Body of the async function that `TestHooks` runs in the page once the web app is ready, through
// `LIQUIDGRAM_TEST_SELFTEST_SCRIPT`. It checks what the web app needs from the iOS web view and returns a JSON report,
// `{ "ok": boolean, "checks": [{ "name", "ok", "detail" }], "info": {...} }`. Every check has a time limit, so the
// report always arrives. `page-errors.js` must run at document start for the `noPageErrors` check.
'use strict';

const CHECK_TIMEOUT_MS = 10000;
const RANGE_START = 100;
const RANGE_LENGTH = 1024;
const STORAGE_KEY = 'liquidgram-selftest';
const DATABASE_NAME = 'liquidgram-selftest';
const DATABASE_STORE = 'items';
const MAX_REPORTED_ERRORS = 5;
// `run-ui-tests.sh` adds this echo worker to the web build of the test app. The production Content-Security-Policy
// has `worker-src 'self'`, which allows workers from the app's own files, the way the web app runs GramJS, and
// blocks `blob:` workers.
const SELFTEST_WORKER_URL = './liquidgram-selftest-worker.js';
const BLOB_WORKER_SOURCE = 'self.onmessage = (e) => { self.postMessage({ pong: e.data && e.data.ping }); };';
// A WebAssembly module that exports `add(i32, i32): i32`
const WASM_ADD_MODULE = [
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
  0x01, 0x07, 0x01, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x07, 0x01, 0x03, 0x61, 0x64, 0x64, 0x00, 0x00,
  0x0a, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6a, 0x0b,
];
const SHA256_OF_ABC = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

const checks = [];

await runCheck('bridge', () => {
  const native = window.__liquidgramNative;
  assert(native, '`window.__liquidgramNative` is missing');
  assert(native.platform === 'ios', `platform is ${native.platform}`);
  assert(native.isBridgeInstalled === true, '`bridge.js` did not run');
  return `version ${native.version}, notification permission ${native.notificationPermission}`;
});

await runCheck('notificationBridge', () => {
  const NotificationClass = window.Notification;
  assert(typeof NotificationClass === 'function', '`window.Notification` is missing');
  assert(!isNativeCode(NotificationClass), '`window.Notification` is the native class, not the one of `bridge.js`');
  assert(typeof NotificationClass.requestPermission === 'function', '`Notification.requestPermission` is missing');
  assert(['default', 'granted', 'denied'].includes(NotificationClass.permission),
    `\`Notification.permission\` is ${NotificationClass.permission}`);
  return `permission ${NotificationClass.permission}`;
});

await runCheck('noServiceWorker', async () => {
  const container = navigator.serviceWorker;
  if (!container) return 'service workers are unavailable';

  assert(!container.controller, `a service worker controls the page: ${container.controller && container.controller.scriptURL}`);
  const registrations = typeof container.getRegistrations === 'function' ? await container.getRegistrations() : [];
  assert(!registrations.length, `${registrations.length} service worker registrations`);
  return 'no controller and no registrations';
});

await runCheck('secureContext', () => {
  assert(window.isSecureContext === true, `\`isSecureContext\` is ${window.isSecureContext}`);
  return location.origin;
});

await runCheck('webCrypto', async () => {
  assert(window.crypto && window.crypto.subtle, '`crypto.subtle` is missing');
  const digest = await window.crypto.subtle.digest('SHA-256', new TextEncoder().encode('abc'));
  const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
  assert(hex === SHA256_OF_ABC, `SHA-256 of "abc" is ${hex}`);
  return 'SHA-256 digest matches';
});

await runCheck('localStorage', () => {
  const value = String(Math.random());
  localStorage.setItem(STORAGE_KEY, value);
  const readValue = localStorage.getItem(STORAGE_KEY);
  localStorage.removeItem(STORAGE_KEY);
  assert(readValue === value, `read ${readValue} instead of ${value}`);
  return 'write, read and remove work';
});

await runCheck('indexedDb', async () => {
  assert(window.indexedDB, '`indexedDB` is missing');
  const database = await openDatabase();
  try {
    const value = String(Math.random());
    await runTransaction(database, 'readwrite', (store) => store.put({ id: 1, value }));
    const item = await runTransaction(database, 'readonly', (store) => store.get(1));
    assert(item && item.value === value, `read ${JSON.stringify(item)}`);
  } finally {
    database.close();
    indexedDB.deleteDatabase(DATABASE_NAME);
  }
  return 'open, put and get work';
});

await runCheck('webAssembly', async () => {
  assert(typeof WebAssembly === 'object', '`WebAssembly` is missing');
  const { instance } = await WebAssembly.instantiate(new Uint8Array(WASM_ADD_MODULE));
  const sum = instance.exports.add(2, 3);
  assert(sum === 5, `add(2, 3) returned ${sum}`);
  return 'a module compiles and runs';
});

await runCheck('worker', async () => {
  const answer = await askWorker(new Worker(SELFTEST_WORKER_URL, { type: 'module' }));
  return `a module worker from the app's origin answered (secure context ${answer.isSecureContext})`;
});

await runCheck('fetchIndex', async () => {
  const response = await fetch('./', { cache: 'no-store' });
  assert(response.status === 200, `status ${response.status}`);
  const contentType = response.headers.get('content-type') || '';
  assert(contentType.startsWith('text/html'), `content type ${contentType}`);
  return `status 200, ${contentType}`;
});

await runCheck('rangeRequest', async () => {
  const script = document.querySelector('script[type="module"][src*="assets/"]');
  assert(script, 'no module script from `assets/` in the page');
  const url = script.src;
  const fullResponse = await fetch(url, { cache: 'no-store' });
  assert(fullResponse.status === 200, `full request: status ${fullResponse.status}`);
  const full = new Uint8Array(await fullResponse.arrayBuffer());
  assert(full.length > RANGE_START + RANGE_LENGTH, `the file has only ${full.length} bytes`);

  const lastByte = RANGE_START + RANGE_LENGTH - 1;
  const response = await fetch(url, { cache: 'no-store', headers: { Range: `bytes=${RANGE_START}-${lastByte}` } });
  assert(response.status === 206, `range request: status ${response.status}`);
  const contentRange = response.headers.get('content-range');
  const expectedRange = `bytes ${RANGE_START}-${lastByte}/${full.length}`;
  assert(contentRange === expectedRange, `Content-Range is ${contentRange}, expected ${expectedRange}`);
  const part = new Uint8Array(await response.arrayBuffer());
  assert(part.length === RANGE_LENGTH, `received ${part.length} bytes instead of ${RANGE_LENGTH}`);
  assert(part.every((byte, index) => byte === full[RANGE_START + index]), 'the bytes differ from the file');
  return `${new URL(url).pathname}: 206 with ${expectedRange}`;
});

await runCheck('userAgentMobile', () => {
  assert(navigator.userAgent.includes('Mobile/'), `no "Mobile/" in ${navigator.userAgent}`);
  return navigator.userAgent;
});

await runCheck('userAgentLiquidgram', () => {
  assert(navigator.userAgent.includes('Liquidgram'), `no "Liquidgram" in ${navigator.userAgent}`);
  return navigator.userAgent;
});

await runCheck('appRendered', () => {
  const root = document.querySelector('#root');
  assert(root, 'no `#root` element');
  const rendered = Array.from(root.children)
    .filter((element) => !['SCRIPT', 'NOSCRIPT', 'STYLE'].includes(element.tagName) && element.id !== 'portals');
  assert(rendered.length, '`#root` has no element of the app');
  return rendered.map((element) => element.id || element.getAttribute('class') || element.tagName).join(', ');
});

await runCheck('compatTest', () => {
  assert(window.isCompatTestPassed === true, 'the browser compatibility test of `compatTest.js` did not pass');
  return 'passed';
});

await runCheck('noPageErrors', () => {
  const errors = window.__liquidgramTestErrors;
  assert(Array.isArray(errors), '`page-errors.js` did not run at document start');
  assert(!errors.length, `${errors.length} errors: ${errors.slice(0, MAX_REPORTED_ERRORS).join(' | ')}`);
  return 'none since the page started';
});

const info = {
  url: location.href,
  userAgent: navigator.userAgent,
  language: navigator.language,
  viewport: `${window.innerWidth}x${window.innerHeight} at ${window.devicePixelRatio}x`,
  colorScheme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light',
  backdropFilter: CSS.supports('backdrop-filter', 'blur(1px)') || CSS.supports('-webkit-backdrop-filter', 'blur(1px)'),
  blobWorker: await describeBlobWorker(),
  authScreen: Boolean(document.querySelector('#auth-api-credentials-form')),
};

return JSON.stringify({ ok: checks.every((check) => check.ok), checks, info });

async function runCheck(name, check) {
  try {
    const detail = await withTimeout(Promise.resolve().then(check));
    checks.push({ name, ok: true, detail: String(detail) });
  } catch (err) {
    checks.push({ name, ok: false, detail: describeError(err) });
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function withTimeout(promise) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`no result in ${CHECK_TIMEOUT_MS} ms`)), CHECK_TIMEOUT_MS);
    promise.then((value) => {
      clearTimeout(timeout);
      resolve(value);
    }, (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

function askWorker(worker) {
  const ping = String(Math.random());
  return new Promise((resolve, reject) => {
    worker.onmessage = (e) => {
      worker.terminate();
      if (e.data && e.data.pong === ping) {
        resolve(e.data);
      } else {
        reject(new Error(`unexpected answer ${JSON.stringify(e.data)}`));
      }
    };
    worker.onerror = (e) => {
      worker.terminate();
      reject(new Error(`worker error: ${e.message || 'the script did not load'}`));
    };
    worker.postMessage({ ping });
  });
}

// For the report only: the production Content-Security-Policy blocks `blob:` workers by design
async function describeBlobWorker() {
  let url;
  try {
    url = URL.createObjectURL(new Blob([BLOB_WORKER_SOURCE], { type: 'text/javascript' }));
    await withTimeout(askWorker(new Worker(url)));
    return 'answered';
  } catch (err) {
    return `blocked: ${describeError(err)}`;
  } finally {
    if (url) URL.revokeObjectURL(url);
  }
}

function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore(DATABASE_STORE, { keyPath: 'id' });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error('`indexedDB.open` failed'));
    request.onblocked = () => reject(new Error('`indexedDB.open` is blocked'));
  });
}

function runTransaction(database, mode, makeRequest) {
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(DATABASE_STORE, mode);
    const request = makeRequest(transaction.objectStore(DATABASE_STORE));
    transaction.oncomplete = () => resolve(request.result);
    transaction.onerror = () => reject(transaction.error || new Error('the transaction failed'));
    transaction.onabort = () => reject(transaction.error || new Error('the transaction was aborted'));
  });
}

function isNativeCode(fn) {
  return /\[native code\]/.test(Function.prototype.toString.call(fn));
}

function describeError(err) {
  if (err instanceof Error) return `${err.name}: ${err.message}`;
  return String(err);
}
