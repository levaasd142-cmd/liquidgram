// Replaces the GramJS worker, like `offline-api.js`, with one that never reaches Telegram but downloads test media: it
// answers `initApi` and pings, so the web app's API calls go out, and `downloadMedia` for the files a test puts into
// `window.__liquidgramTestMedia.files`, by the media hash in the URL. Every other call stays unanswered, so a stored
// session stays on its cached state. `window.__liquidgramTestMedia.requests` records the downloads. The tests inject
// it at document start through `LIQUIDGRAM_TEST_USER_SCRIPT`, instead of `offline-api.js`.
(() => {
  'use strict';

  // GramJS runs in `worker-<hash>.js` in production and in `worker.ts` in development
  const API_WORKER_PATH = /(^|\/)worker(-[\w-]+)?\.(js|ts)$/;
  const MEDIA_HASH = /\/progressive\/([\w-]+)/;

  const NativeWorker = window.Worker;
  if (typeof NativeWorker !== 'function') return;

  const testMedia = { files: {}, requests: [] };
  Object.defineProperty(window, '__liquidgramTestMedia', { value: testMedia });

  class MediaApiWorker extends EventTarget {
    constructor() {
      super();
      this.onmessage = undefined;
      this.onmessageerror = undefined;
      this.onerror = undefined;
    }

    postMessage(data) {
      const payloads = data && Array.isArray(data.payloads) ? data.payloads : [];
      payloads.forEach((payload) => {
        // The web app pings its worker when the window gets the focus and restarts one that does not answer
        if ((payload.type === 'initApi' || payload.type === 'ping') && payload.messageId) {
          this.respond({ type: 'methodResponse', messageId: payload.messageId, response: true });
        } else if (payload.type === 'callMethod' && payload.name === 'downloadMedia' && payload.messageId) {
          this.download(payload.messageId, payload.args[0]);
        }
      });
    }

    terminate() {}

    download(messageId, params) {
      const match = params && typeof params.url === 'string' && params.url.match(MEDIA_HASH);
      const file = match && testMedia.files[match[1]];
      if (!file) return;

      const { start = 0, end = file.bytes.length - 1 } = params;
      testMedia.requests.push({ hash: match[1], start, end, at: performance.now() });
      const arrayBuffer = file.bytes.slice(start, Math.min(end + 1, file.bytes.length)).buffer;
      setTimeout(() => {
        this.respond({
          type: 'methodResponse',
          messageId,
          response: {
            dataBlob: '', arrayBuffer, mimeType: file.mimeType, fullSize: file.bytes.length,
          },
        });
      }, file.delay || 0);
    }

    respond(payload) {
      const event = new MessageEvent('message', { data: { payloads: [payload] } });
      if (typeof this.onmessage === 'function') this.onmessage(event);
      this.dispatchEvent(event);
    }
  }

  function MediaWorker(url, options) {
    if (isApiWorkerUrl(url)) {
      return new MediaApiWorker();
    }

    return new NativeWorker(url, options);
  }

  MediaWorker.prototype = NativeWorker.prototype;
  Object.defineProperty(window, 'Worker', { configurable: true, writable: true, value: MediaWorker });

  function isApiWorkerUrl(url) {
    try {
      return API_WORKER_PATH.test(new URL(String(url), document.baseURI).pathname);
    } catch (err) {
      return false;
    }
  }
})();
