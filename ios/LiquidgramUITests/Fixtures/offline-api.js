// Keeps a stored session of the web app offline for the UI tests: the GramJS worker, the only part of the web app that
// connects to Telegram, is replaced with one that never answers, so the app stays on its cached state and nothing
// reaches Telegram. The tests inject it at document start through `LIQUIDGRAM_TEST_USER_SCRIPT`, before the app's
// scripts, together with `demo-account.js` or on its own when the app restarts with a stored session.
(() => {
  'use strict';

  // GramJS runs in `worker-<hash>.js` in production and in `worker.ts` in development
  const API_WORKER_PATH = /(^|\/)worker(-[\w-]+)?\.(js|ts)$/;

  const NativeWorker = window.Worker;
  if (typeof NativeWorker !== 'function') return;

  class OfflineApiWorker extends EventTarget {
    constructor() {
      super();
      this.onmessage = undefined;
      this.onmessageerror = undefined;
      this.onerror = undefined;
    }

    postMessage() {}

    terminate() {}
  }

  function OfflineWorker(url, options) {
    if (isApiWorkerUrl(url)) {
      return new OfflineApiWorker();
    }

    return new NativeWorker(url, options);
  }

  OfflineWorker.prototype = NativeWorker.prototype;
  Object.defineProperty(window, 'Worker', { configurable: true, writable: true, value: OfflineWorker });

  function isApiWorkerUrl(url) {
    try {
      return API_WORKER_PATH.test(new URL(String(url), document.baseURI).pathname);
    } catch (err) {
      return false;
    }
  }
})();
