// Checks that the probe runs inside the real web app once it rendered: the app imports nothing from here, the native
// side calls `runChecks()` through `callAsyncJavaScript` and records the results
const ANSWER_TIMEOUT_MS = 15000;
// `APP_NAME` of the build, which names the shared state worker
const APP_NAME = 'Liquidgram';

export async function runChecks() {
  const info = await (await fetch('/__probe/build-info.json', { cache: 'no-store' })).json();
  return [
    await run('realapp-api-keys-screen', checkApiKeysScreen),
    await run('realapp-gramjs-worker', () => pingGramJsWorker(info.gramjsWorker)),
    await run('realapp-sharedstate-worker', () => askSharedStateWorker(info.sharedStateWorker)),
    await run('info-realapp-environment', describeEnvironment),
  ];
}

async function run(name, check) {
  try {
    return { name, ok: true, detail: describe(await check()) };
  } catch (err) {
    return { name, ok: false, detail: describe(err) };
  }
}

function describe(value) {
  if (value instanceof Error) return `${value.name}: ${value.message}`;
  if (typeof value === 'string') return value;
  return JSON.stringify(value);
}

function checkApiKeysScreen() {
  const form = document.querySelector('#auth-api-credentials-form');
  if (!form) throw new Error(`no API keys form, the page shows: ${document.body.innerText.slice(0, 200)}`);
  const rect = form.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) throw new Error('the form is not visible');
  if (!document.querySelector('#liquid-api-id') || !document.querySelector('#liquid-api-hash')) {
    throw new Error('the API id or API hash field is missing');
  }
  const heading = form.querySelector('h1');
  return { heading: heading ? heading.textContent : undefined, text: form.innerText.replace(/\s+/g, ' ').slice(0, 160) };
}

// Starts the GramJS worker of the build the way `src/api/gramjs/worker/connector.ts` does and sends the `ping` of
// its protocol, which needs no network and no API keys
function pingGramJsWorker(fileName) {
  const url = new URL(fileName, document.baseURI).href;
  const startedAt = performance.now();
  return new Promise((resolve, reject) => {
    const worker = new Worker(url, { name: '', type: 'module' });
    const timer = setTimeout(() => {
      worker.terminate();
      reject(new Error(`${url} did not answer the ping`));
    }, ANSWER_TIMEOUT_MS);
    worker.onmessage = (e) => {
      const payloads = (e.data && e.data.payloads) || [];
      if (!payloads.some((payload) => payload.type === 'methodResponse' && payload.messageId === 'probe-ping')) return;
      clearTimeout(timer);
      worker.terminate();
      resolve(`${url} answered the ping in ${Math.round(performance.now() - startedAt)} ms`);
    };
    worker.onerror = (e) => {
      clearTimeout(timer);
      worker.terminate();
      reject(new Error(`${url}: ${e.message || 'the script did not load'}`));
    };
    worker.postMessage({ payloads: [{ type: 'ping', messageId: 'probe-ping' }] });
  });
}

// Connects to the shared state worker with the options of `createSharedWorker()` and asks for a passcode key of an
// unknown generation, which the worker answers without changing its state
function askSharedStateWorker(fileName) {
  if (typeof SharedWorker !== 'function') throw new Error('SharedWorker is missing');
  const url = new URL(fileName, document.baseURI).href;
  const generation = `probe-${Date.now()}`;
  return new Promise((resolve, reject) => {
    const worker = new SharedWorker(url, { name: APP_NAME, type: 'module', extendedLifetime: true });
    const timer = setTimeout(() => {
      worker.port.close();
      reject(new Error(`${url} did not answer`));
    }, ANSWER_TIMEOUT_MS);
    worker.onerror = (e) => {
      clearTimeout(timer);
      reject(new Error(`${url}: ${e.message || 'the script did not load'}`));
    };
    worker.port.onmessage = (e) => {
      if (!e.data || e.data.type !== 'passcodeNavigationDek' || e.data.generation !== generation) return;
      clearTimeout(timer);
      worker.port.close();
      resolve(`${url} answered`);
    };
    worker.port.postMessage({ type: 'requestPasscodeNavigationDek', generation });
  });
}

function describeEnvironment() {
  return {
    origin: window.location.origin,
    isSecureContext: window.isSecureContext,
    title: document.title,
    isIosApp: Boolean(window.__liquidgramNative),
    hasServiceWorkerController: Boolean(navigator.serviceWorker && navigator.serviceWorker.controller),
    resources: performance.getEntriesByType('resource').length,
  };
}
