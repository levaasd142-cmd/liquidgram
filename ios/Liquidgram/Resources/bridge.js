// Liquidgram iOS bridge. The app injects it into the main frame at document start, right after the line that sets
// `window.__liquidgramNative`, so it runs before any page script. It gives the web build what `WKWebView` lacks:
// `Notification`, shown as local notifications of the app, `navigator.setAppBadge`, shown on the app icon, and
// `navigator.vibrate`, played as haptic feedback. Uncaught errors go to the app's log. Messages go to the app through
// `window.webkit.messageHandlers.liquidgram`; the app answers through the functions this script adds to
// `window.__liquidgramNative`.
//
// The web app talks to the app through these members of `window.__liquidgramNative`, each of them optional:
// - `request(type, payload)` posts `{ type, requestId, ...payload }` and returns a promise of the app's response
//   object, which the app passes to `resolveRequest(requestId, response)`. It rejects after 30 seconds without one.
// - `haptic(style)` plays feedback: 'selection', 'light', 'medium', 'heavy', 'soft', 'rigid', 'success', 'warning'
//   or 'error'.
// - `postMessage(message)` posts `{ type, ... }` without an answer, such as `{ type: 'lockNow' }`.
// - `setActionHandler(handler)` receives the app's actions, such as `{ type: 'openSearch' }`, and tells the app with
//   `{ type: 'appReady' }` that the page can take them. The app calls `dispatchAction(action)`; actions that arrive
//   before a handler is set wait for it.
// The script runs once per page, and running it again changes nothing. Plain ES2019, so that every iOS 16
// `WKWebView` runs it.
(() => {
  'use strict';

  const native = window.__liquidgramNative;
  if (!native || native.isBridgeInstalled) return;

  Object.defineProperty(native, 'isBridgeInstalled', { value: true });

  const PERMISSION_STATES = ['default', 'granted', 'denied'];
  const EVENT_TYPES = ['click', 'close', 'error', 'show'];
  const HAPTIC_STYLES = ['selection', 'light', 'medium', 'heavy', 'soft', 'rigid', 'success', 'warning', 'error'];
  // A single vibration feels like a tap, a pattern like an alert
  const VIBRATION_STYLE = 'medium';
  const VIBRATION_PATTERN_STYLE = 'warning';
  const REQUEST_TIMEOUT = 30000;
  const MAX_PENDING_ACTIONS = 20;
  // Identifiers for notifications without a tag, unique across page loads
  const UNTAGGED_PREFIX = `untagged-${Date.now().toString(36)}-`;
  // `setAppBadge()` without a count asks for a plain mark, and an iOS app icon shows only numbers
  const MARK_BADGE_COUNT = 1;
  const MAX_LOG_MESSAGES = 100;

  const statesByNotification = new WeakMap();
  // Notifications on screen by the identifier the app shows them with, so a tap reaches the right instance
  const notificationsByTag = new Map();
  const permissionRequests = new Map();
  const nativeRequests = new Map();
  const pendingActions = [];
  let lastRequestId = 0;
  let lastNativeRequestId = 0;
  let lastUntaggedId = 0;
  let lastBadgeCount;
  let logMessagesCount = 0;
  let actionHandler;
  let isActionFlushScheduled = false;

  class Notification extends EventTarget {
    static get permission() {
      return normalizePermission(native.notificationPermission);
    }

    static requestPermission(deprecatedCallback) {
      return requestPermission(deprecatedCallback);
    }

    constructor(title, options) {
      if (!arguments.length) {
        throw new TypeError('Failed to construct \'Notification\': 1 argument required, but only 0 present.');
      }

      super();

      const {
        tag = '', body = '', icon, data = null, silent = null,
      } = options || {};
      const state = {
        title: String(title),
        body: String(body),
        tag: String(tag),
        icon: icon === undefined ? '' : resolveUrl(icon),
        data,
        silent: silent === null ? null : Boolean(silent),
        handlers: {},
        listeningTypes: new Set(),
        nativeTag: undefined,
      };
      statesByNotification.set(this, state);

      showNotification(this, state);
    }

    get title() {
      return getState(this).title;
    }

    get body() {
      return getState(this).body;
    }

    get tag() {
      return getState(this).tag;
    }

    get icon() {
      return getState(this).icon;
    }

    get data() {
      return getState(this).data;
    }

    get silent() {
      return getState(this).silent;
    }

    close() {
      const { nativeTag } = getState(this);
      if (nativeTag === undefined || notificationsByTag.get(nativeTag) !== this) return;

      notificationsByTag.delete(nativeTag);
      postToNative({ type: 'closeNotification', tag: nativeTag });
      queueEvent(this, 'close');
    }
  }

  EVENT_TYPES.forEach((type) => {
    Object.defineProperty(Notification.prototype, `on${type}`, {
      configurable: true,
      enumerable: true,
      get() {
        const handler = getState(this).handlers[type];
        // The Notifications API reports a missing handler as `null`
        return handler === undefined ? null : handler;
      },
      set(handler) {
        const state = getState(this);
        state.handlers[type] = typeof handler === 'function' ? handler : undefined;
        // Like an HTML event handler, it starts listening when first set, after the listeners added before
        if (!state.handlers[type] || state.listeningTypes.has(type)) return;

        state.listeningTypes.add(type);
        this.addEventListener(type, (e) => {
          const currentHandler = state.handlers[type];
          if (currentHandler && currentHandler.call(this, e) === false) {
            e.preventDefault();
          }
        });
      },
    });
  });

  native.notificationPermission = normalizePermission(native.notificationPermission);
  native.resolvePermission = resolvePermission;
  native.setPermission = setPermission;
  native.notificationClicked = handleNotificationClick;
  native.request = request;
  native.resolveRequest = resolveRequest;
  native.haptic = haptic;
  native.postMessage = postMessage;
  native.setActionHandler = setActionHandler;
  native.dispatchAction = dispatchAction;

  defineValue(window, 'Notification', Notification);
  // Telegram Web A reports the unread count through the Badging API, see `src/util/appBadge.ts`
  defineValue(navigator, 'setAppBadge', setAppBadge);
  defineValue(navigator, 'clearAppBadge', clearAppBadge);
  if (typeof navigator.vibrate !== 'function') {
    defineValue(navigator, 'vibrate', vibrate);
  }

  window.addEventListener('error', handleError);
  window.addEventListener('unhandledrejection', handleUnhandledRejection);

  function showNotification(notification, state) {
    if (Notification.permission !== 'granted') {
      queueEvent(notification, 'error');
      return;
    }

    const nativeTag = state.tag || `${UNTAGGED_PREFIX}${++lastUntaggedId}`;
    if (!postToNative({
      type: 'notify', tag: nativeTag, title: state.title, body: state.body,
    })) {
      queueEvent(notification, 'error');
      return;
    }

    // The app shows the new notification in place of the one with the same tag, which closes
    const replacedNotification = notificationsByTag.get(nativeTag);
    if (replacedNotification) {
      queueEvent(replacedNotification, 'close');
    }

    state.nativeTag = nativeTag;
    notificationsByTag.set(nativeTag, notification);
    queueEvent(notification, 'show');
  }

  function handleNotificationClick(tag) {
    const nativeTag = String(tag);
    const notification = notificationsByTag.get(nativeTag);
    if (!notification) return;

    notification.dispatchEvent(new Event('click', { cancelable: true }));

    // iOS removes a notification from the Notification Center once the user taps it
    if (notificationsByTag.get(nativeTag) === notification) {
      notificationsByTag.delete(nativeTag);
      queueEvent(notification, 'close');
    }
  }

  function requestPermission(deprecatedCallback) {
    return new Promise((resolve) => {
      const requestId = ++lastRequestId;
      permissionRequests.set(requestId, (permission) => {
        if (typeof deprecatedCallback === 'function') {
          try {
            deprecatedCallback(permission);
          } catch (err) {
            rethrowLater(err);
          }
        }

        resolve(permission);
      });

      if (!postToNative({ type: 'requestNotificationPermission', requestId })) {
        resolvePermission(requestId, Notification.permission);
      }
    });
  }

  function resolvePermission(requestId, permission) {
    setPermission(permission);

    const id = Number(requestId);
    const settle = permissionRequests.get(id);
    if (!settle) return;

    permissionRequests.delete(id);
    settle(Notification.permission);
  }

  function setPermission(permission) {
    native.notificationPermission = normalizePermission(permission);
  }

  function request(type, payload) {
    return new Promise((resolve, reject) => {
      if (typeof type !== 'string') {
        reject(new TypeError('The request type must be a string'));
        return;
      }

      const requestId = ++lastNativeRequestId;
      const timeout = setTimeout(() => {
        nativeRequests.delete(requestId);
        reject(new Error(`The app did not answer the ${type} request`));
      }, REQUEST_TIMEOUT);
      nativeRequests.set(requestId, { resolve, timeout });

      // The type and the id always win over fields of the same name in the payload
      if (!postToNative(Object.assign({}, payload, { type, requestId }))) {
        clearTimeout(timeout);
        nativeRequests.delete(requestId);
        reject(new Error('The app is not available'));
      }
    });
  }

  function resolveRequest(requestId, response) {
    const id = Number(requestId);
    const pendingRequest = nativeRequests.get(id);
    if (!pendingRequest) return;

    nativeRequests.delete(id);
    clearTimeout(pendingRequest.timeout);
    pendingRequest.resolve(response);
  }

  function haptic(style) {
    if (!HAPTIC_STYLES.includes(style)) return;

    postToNative({ type: 'haptic', style });
  }

  function postMessage(message) {
    if (!message || typeof message.type !== 'string') return;

    postToNative(message);
  }

  function setActionHandler(handler) {
    actionHandler = typeof handler === 'function' ? handler : undefined;
    if (!actionHandler) return;

    // Every call announces readiness again, so a remounted app gets the actions that arrive afterwards
    postToNative({ type: 'appReady' });
    scheduleActionFlush();
  }

  function dispatchAction(action) {
    if (!action || typeof action !== 'object' || typeof action.type !== 'string') return;

    if (pendingActions.length >= MAX_PENDING_ACTIONS) {
      pendingActions.shift();
    }
    pendingActions.push(action);
    if (actionHandler && !isActionFlushScheduled) {
      flushActions();
    }
  }

  // Actions that waited for a handler run after the code that set it has finished
  function scheduleActionFlush() {
    if (isActionFlushScheduled) return;

    isActionFlushScheduled = true;
    setTimeout(() => {
      isActionFlushScheduled = false;
      flushActions();
    }, 0);
  }

  function flushActions() {
    while (actionHandler && pendingActions.length) {
      const action = pendingActions.shift();
      try {
        actionHandler(action);
      } catch (err) {
        rethrowLater(err);
      }
    }
  }

  // Only the vibrations of a pattern count; the entries between them are pauses
  function vibrate(pattern) {
    const durations = Array.isArray(pattern) ? pattern : [pattern];
    const vibratesAtAll = durations.some((duration, index) => index % 2 === 0 && Number(duration) > 0);
    if (vibratesAtAll) {
      haptic(durations.length > 1 ? VIBRATION_PATTERN_STYLE : VIBRATION_STYLE);
    }

    return true;
  }

  function setAppBadge(contents) {
    const count = contents === undefined ? MARK_BADGE_COUNT : Math.trunc(Number(contents));
    if (!Number.isSafeInteger(count) || count < 0) {
      return Promise.reject(new TypeError('The badge count must be a non-negative integer'));
    }

    postBadge(count);
    return Promise.resolve();
  }

  function clearAppBadge() {
    postBadge(0);
    return Promise.resolve();
  }

  function postBadge(count) {
    if (count === lastBadgeCount || !postToNative({ type: 'badge', count })) return;

    lastBadgeCount = count;
  }

  function handleError(e) {
    const stack = e.error instanceof Error && e.error.stack ? `\n${e.error.stack}` : '';
    postLog(`${e.message} at ${e.filename}:${e.lineno}:${e.colno}${stack}`);
  }

  function handleUnhandledRejection(e) {
    postLog(`Unhandled rejection: ${describeError(e.reason)}`);
  }

  function postLog(message) {
    if (logMessagesCount >= MAX_LOG_MESSAGES) return;

    logMessagesCount += 1;
    postToNative({ type: 'log', level: 'error', message });
  }

  function postToNative(message) {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.liquidgram;
    if (!handler || typeof handler.postMessage !== 'function') return false;

    try {
      handler.postMessage(message);
      return true;
    } catch (err) {
      return false;
    }
  }

  function queueEvent(target, type) {
    setTimeout(() => {
      target.dispatchEvent(new Event(type));
    }, 0);
  }

  function getState(notification) {
    const state = statesByNotification.get(notification);
    if (!state) throw new TypeError('Illegal invocation');

    return state;
  }

  function normalizePermission(permission) {
    return PERMISSION_STATES.includes(permission) ? permission : 'default';
  }

  function resolveUrl(url) {
    try {
      return new URL(String(url), document.baseURI).href;
    } catch (err) {
      return '';
    }
  }

  function describeError(err) {
    try {
      const text = String(err);
      const stack = err instanceof Error ? err.stack : undefined;
      // A WebKit stack lacks the message that a Chromium stack starts with
      return stack && !stack.startsWith(text) ? `${text}\n${stack}` : stack || text;
    } catch (stringifyErr) {
      return Object.prototype.toString.call(err);
    }
  }

  // Reports an exception without interrupting the caller, as browsers do for a callback that throws
  function rethrowLater(err) {
    setTimeout(() => {
      throw err;
    }, 0);
  }

  function defineValue(target, key, value) {
    Object.defineProperty(target, key, { configurable: true, writable: true, value });
  }
})();
