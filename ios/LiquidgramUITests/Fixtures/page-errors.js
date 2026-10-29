// Records uncaught errors and unhandled promise rejections of the page from the first script on, so the self-test can
// report them. The tests inject it at document start through `LIQUIDGRAM_TEST_USER_SCRIPT`, before the app's scripts.
(() => {
  'use strict';

  if (window.__liquidgramTestErrors) return;

  const MAX_ERRORS = 20;
  const MAX_MESSAGE_LENGTH = 500;
  const errors = [];

  Object.defineProperty(window, '__liquidgramTestErrors', { value: errors });

  window.addEventListener('error', (e) => {
    record(`${e.message} at ${e.filename}:${e.lineno}:${e.colno}`);
  });
  window.addEventListener('unhandledrejection', (e) => {
    record(`Unhandled rejection: ${describe(e.reason)}`);
  });

  function record(message) {
    if (errors.length >= MAX_ERRORS) return;

    errors.push(String(message).slice(0, MAX_MESSAGE_LENGTH));
  }

  function describe(reason) {
    try {
      return reason instanceof Error ? `${reason.name}: ${reason.message}` : String(reason);
    } catch (err) {
      return Object.prototype.toString.call(reason);
    }
  }
})();
