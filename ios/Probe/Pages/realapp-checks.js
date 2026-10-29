// Checks that the probe runs inside the real web app once it rendered: the app imports nothing from here, the native
// side calls `runChecks()` through `callAsyncJavaScript` and records the results
const ANSWER_TIMEOUT_MS = 15000;
// `APP_NAME` of the build, which names the shared state worker
const APP_NAME = 'Liquidgram';
// The format of voice messages that `src/util/oggToWav.ts` converts
const VOICE_SAMPLE_RATE = 48000;
const VOICE_BIT_DEPTH = 16;

export async function runChecks() {
  const info = await (await fetch('/__probe/build-info.json', { cache: 'no-store' })).json();
  return [
    await run('realapp-api-keys-screen', checkApiKeysScreen),
    await run('realapp-gramjs-worker', () => pingGramJsWorker(info.gramjsWorker)),
    await run('realapp-sharedstate-worker', () => askSharedStateWorker(info.sharedStateWorker)),
    await run('realapp-voice-decoder', () => decodeVoiceMessage(info.decoderWorker, info.waveWorker)),
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

// Converts an OGG Opus voice message to WAV with the decoder and wave workers of the build, exactly as
// `src/util/oggToWav.ts` does for voice messages, then loads the WAV from a `blob:` URL. The decoder worker loads
// its WebAssembly module from the build itself.
async function decodeVoiceMessage(decoderFileName, waveFileName) {
  const ogg = new Uint8Array(await (await fetch('/__probe/probe-voice.ogg', { cache: 'no-store' })).arrayBuffer());
  const oggLength = ogg.length;
  const wav = await new Promise((resolve, reject) => {
    const decoderWorker = new Worker(new URL(decoderFileName, document.baseURI).href);
    const waveWorker = new Worker(new URL(waveFileName, document.baseURI).href);
    const timer = setTimeout(() => {
      stop();
      reject(new Error('no WAV page from the workers'));
    }, ANSWER_TIMEOUT_MS);
    function stop() {
      clearTimeout(timer);
      decoderWorker.terminate();
      waveWorker.terminate();
    }
    decoderWorker.onerror = (e) => {
      stop();
      reject(new Error(`decoder worker: ${e.message || 'the script did not load'}`));
    };
    waveWorker.onerror = (e) => {
      stop();
      reject(new Error(`wave worker: ${e.message || 'the script did not load'}`));
    };
    decoderWorker.onmessage = (e) => {
      // `null` means the decoder is finished
      if (e.data === null) {
        waveWorker.postMessage({ command: 'done' });
        return;
      }
      waveWorker.postMessage({ command: 'encode', buffers: e.data }, e.data.map(({ buffer }) => buffer));
    };
    waveWorker.onmessage = (e) => {
      if (e.data.message !== 'page') return;
      stop();
      resolve(new Blob([e.data.page], { type: 'audio/wav' }));
    };
    waveWorker.postMessage({ command: 'init', wavBitDepth: VOICE_BIT_DEPTH, wavSampleRate: VOICE_SAMPLE_RATE });
    decoderWorker.postMessage({
      command: 'init', decoderSampleRate: VOICE_SAMPLE_RATE, outputBufferSampleRate: VOICE_SAMPLE_RATE,
    });
    decoderWorker.postMessage({ command: 'decode', pages: ogg }, [ogg.buffer]);
  });

  const url = URL.createObjectURL(wav);
  try {
    const audio = new Audio();
    audio.muted = true;
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('the WAV did not load')), ANSWER_TIMEOUT_MS);
      audio.onloadedmetadata = () => {
        clearTimeout(timer);
        resolve();
      };
      audio.onerror = () => {
        clearTimeout(timer);
        reject(new Error(`WAV media error ${audio.error ? audio.error.code : 'unknown'}`));
      };
      audio.src = url;
    });
    return `${oggLength} bytes of OGG Opus became ${wav.size} bytes of WAV lasting ${audio.duration.toFixed(2)} s`;
  } finally {
    URL.revokeObjectURL(url);
  }
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
