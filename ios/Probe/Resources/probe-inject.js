// Injected by the probe app at document start into the main frame of every page, before `bridge.js`. Reports console
// errors and warnings, uncaught errors, unhandled rejections, CSP violations, failed resources and the workers a page
// starts to the `probe` message handler as `{ type, kind, text }`.
(() => {
  if (window.__probePost) return;

  const MAX_TEXT_LENGTH = 3000;

  function post(message) {
    try {
      window.webkit.messageHandlers.probe.postMessage(message);
    } catch (err) {
      // The handler exists only in the probe app
    }
  }

  function describe(value) {
    try {
      if (value instanceof Error) return `${value.name}: ${value.message}${value.stack ? ` | ${value.stack}` : ''}`;
      if (typeof value === 'string') return value;
      return JSON.stringify(value);
    } catch (err) {
      return String(value);
    }
  }

  function join(values) {
    return values.map(describe).join(' ').slice(0, MAX_TEXT_LENGTH);
  }

  Object.defineProperty(window, '__probePost', { value: post });
  Object.defineProperty(window, '__probeInjected', { value: true });

  ['error', 'warn'].forEach((level) => {
    const original = console[level];
    console[level] = function (...args) {
      post({ type: 'console', kind: level, text: join(args) });
      return original.apply(this, args);
    };
  });

  window.addEventListener('error', (e) => {
    const { target } = e;
    if (target && target !== window && (target.src || target.href)) {
      post({ type: 'resource', kind: 'error', text: `${target.tagName} ${target.src || target.href}` });
      return;
    }
    const stack = e.error && e.error.stack ? ` | ${e.error.stack}` : '';
    post({ type: 'uncaught', text: `${e.message} at ${e.filename}:${e.lineno}:${e.colno}${stack}`.slice(0, MAX_TEXT_LENGTH) });
  }, true);

  window.addEventListener('unhandledrejection', (e) => {
    post({ type: 'unhandledrejection', text: join([e.reason]) });
  });

  document.addEventListener('securitypolicyviolation', (e) => {
    post({ type: 'csp', text: `${e.violatedDirective} blocked ${e.blockedURI} at ${e.sourceFile}:${e.lineNumber}` });
  });

  // Records every worker a page starts and whether it loads and answers
  function wrapWorker(name) {
    const Original = window[name];
    if (typeof Original !== 'function') return;

    function ProbeWorker(url, options) {
      const worker = new Original(url, options);
      const label = `${name} ${String(url)} ${options && options.type ? options.type : 'classic'}`;
      post({ type: 'worker', kind: 'create', text: label });
      worker.addEventListener('error', (e) => {
        post({ type: 'worker', kind: 'error', text: `${label}: ${e.message || 'the script did not load'}` });
      });
      let hasAnswered = false;
      (name === 'SharedWorker' ? worker.port : worker).addEventListener('message', () => {
        if (hasAnswered) return;
        hasAnswered = true;
        post({ type: 'worker', kind: 'message', text: label });
      });
      return worker;
    }

    ProbeWorker.prototype = Original.prototype;
    Object.defineProperty(window, name, { configurable: true, writable: true, value: ProbeWorker });
  }

  wrapWorker('Worker');
  wrapWorker('SharedWorker');
})();
