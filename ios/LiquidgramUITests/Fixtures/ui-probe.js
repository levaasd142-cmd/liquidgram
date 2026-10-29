// Lets the UI tests measure the page and act inside it. XCUITest sees web content only through the accessibility
// tree, so this script publishes measurements as the accessibility label of a tiny element and adds buttons that the
// tests tap to run page code. The tests inject it at document start through `LIQUIDGRAM_TEST_USER_SCRIPT` when they
// launch with `Launch(shouldInstallProbe: true)`.
//
// The label is `liquidgram-probe ` followed by JSON:
// - `innerWidth`, `innerHeight`, `clientHeight`, `visualHeight`: the sizes of the layout and visual viewports;
//   `htmlHeight`: the height of the root element; `vh`: the web app's `--vh` variable times 100, in pixels
// - `scrollTop` (`document.scrollingElement`), `scrollY`, `pageTop` and `offsetTop` (`visualViewport`) now, and
//   `max` with the highest value of each since the page started: the page itself never scrolls in the app
// - `safeTop`, `safeBottom`: `env(safe-area-inset-top)` and `env(safe-area-inset-bottom)`
// - `themeColor`: the content of `<meta name="theme-color">`; `theme`: the theme class of the root element
// - `active`: the focused element; `hasFocus`: `document.hasFocus()`; `isInBackground` and `isKeyboardVisible`: whether
//   the web app set `body.in-background`, which pauses its animations, and `body.keyboard-visible`
// Buttons at the left edge of the screen, which the tests find by their labels:
// - `liquidgram-probe-blur` takes the focus from the focused field, which hides the keyboard
// - `liquidgram-probe-open-later` calls `window.open` with a web page 1.5 s after the tap, like the flows that wait
//   for the server before they open a link
(() => {
  'use strict';

  if (window.__liquidgramTestProbe) return;

  Object.defineProperty(window, '__liquidgramTestProbe', { value: true });

  const LABEL_PREFIX = 'liquidgram-probe ';
  const BLUR_LABEL = 'liquidgram-probe-blur';
  const OPEN_LATER_LABEL = 'liquidgram-probe-open-later';
  const OPEN_LATER_URL = 'https://example.com/?liquidgram-ui-test=open-later';
  const OPEN_LATER_DELAY_MS = 1500;
  const UPDATE_INTERVAL_MS = 200;
  // Above every layer of the web app, including its portals and the media viewer
  const Z_INDEX = '2147483647';
  const BUTTON_SIZE_PX = 44;
  // Below the status bar also while WebKit slides the page up for the keyboard, and above the keyboard otherwise
  const BUTTONS_TOP = '55%';
  const VH_TO_HEIGHT = 100;

  const max = {
    scrollTop: 0, scrollY: 0, pageTop: 0, offsetTop: 0,
  };
  let label;
  let insets;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', install);
  } else {
    install();
  }

  function install() {
    label = document.createElement('div');
    label.setAttribute('role', 'img');
    label.style.cssText = `position:fixed;left:0;top:0;width:1px;height:1px;opacity:0.01;pointer-events:none;z-index:${
      Z_INDEX}`;
    document.body.appendChild(label);

    insets = document.createElement('div');
    insets.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;'
      + 'padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)';
    document.body.appendChild(insets);

    addButton(BLUR_LABEL, 0, () => {
      const element = document.activeElement;
      if (element && element !== document.body) element.blur();
    });
    addButton(OPEN_LATER_LABEL, 1, () => {
      setTimeout(() => {
        window.open(OPEN_LATER_URL, '_blank');
      }, OPEN_LATER_DELAY_MS);
    });

    window.addEventListener('scroll', update, { passive: true });
    if (window.visualViewport) {
      window.visualViewport.addEventListener('scroll', update, { passive: true });
      window.visualViewport.addEventListener('resize', update, { passive: true });
    }
    setInterval(update, UPDATE_INTERVAL_MS);
    update();
  }

  function addButton(ariaLabel, index, onClick) {
    const button = document.createElement('button');
    button.type = 'button';
    button.setAttribute('aria-label', ariaLabel);
    button.style.cssText = `position:fixed;left:0;top:calc(${BUTTONS_TOP} + ${index * BUTTON_SIZE_PX}px);`
      + `width:${BUTTON_SIZE_PX}px;height:${BUTTON_SIZE_PX}px;margin:0;padding:0;border:0;opacity:0.01;`
      + `background:#888;z-index:${Z_INDEX}`;
    button.addEventListener('click', (e) => {
      e.stopPropagation();
      onClick();
    });
    document.body.appendChild(button);
  }

  function update() {
    const root = document.documentElement;
    const viewport = window.visualViewport;
    const current = {
      scrollTop: round(document.scrollingElement ? document.scrollingElement.scrollTop : 0),
      scrollY: round(window.scrollY),
      pageTop: round(viewport ? viewport.pageTop : 0),
      offsetTop: round(viewport ? viewport.offsetTop : 0),
    };
    Object.keys(max).forEach((key) => {
      max[key] = Math.max(max[key], current[key]);
    });
    const insetsStyle = getComputedStyle(insets);
    const themeColorTag = document.querySelector('meta[name="theme-color"]');
    const themeClass = Array.from(root.classList).find((name) => name.startsWith('theme-'));
    const vh = parseFloat(getComputedStyle(root).getPropertyValue('--vh'));
    const report = Object.assign(current, {
      max,
      innerWidth: window.innerWidth,
      innerHeight: window.innerHeight,
      clientHeight: root.clientHeight,
      visualHeight: round(viewport ? viewport.height : window.innerHeight),
      htmlHeight: round(root.getBoundingClientRect().height),
      vh: Number.isFinite(vh) ? round(vh * VH_TO_HEIGHT) : undefined,
      safeTop: round(parseFloat(insetsStyle.paddingTop) || 0),
      safeBottom: round(parseFloat(insetsStyle.paddingBottom) || 0),
      themeColor: themeColorTag ? themeColorTag.getAttribute('content') : undefined,
      theme: themeClass ? themeClass.slice('theme-'.length) : undefined,
      active: describeElement(document.activeElement),
      hasFocus: document.hasFocus(),
      isInBackground: document.body.classList.contains('in-background'),
      isKeyboardVisible: document.body.classList.contains('keyboard-visible'),
    });
    const text = LABEL_PREFIX + JSON.stringify(report);
    if (label.getAttribute('aria-label') !== text) {
      label.setAttribute('aria-label', text);
    }
  }

  function describeElement(element) {
    if (!element || element === document.body) return 'body';

    return element.id ? `${element.tagName.toLowerCase()}#${element.id}` : element.tagName.toLowerCase();
  }

  function round(value) {
    return Math.round(value * 10) / 10;
  }
})();
