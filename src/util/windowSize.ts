import type { IDimensions } from '../types';

import { EDITABLE_INPUT_ID, EDITABLE_INPUT_MODAL_ID, EDITABLE_STORY_INPUT_ID } from '../config';
import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import { IS_IOS, IS_IOS_APP } from './browser/windowEnvironment';
import { throttle } from './schedulers';

const WINDOW_ORIENTATION_CHANGE_THROTTLE_MS = 100;
const WINDOW_RESIZE_THROTTLE_MS = 250;
// Space between a field revealed above the keyboard and the keyboard
const FOCUSED_FIELD_MARGIN = 16;
// Composers sit at the bottom of their screens, so they stay above the keyboard by layout
const COMPOSER_INPUT_IDS = new Set([EDITABLE_INPUT_ID, EDITABLE_INPUT_MODAL_ID, EDITABLE_STORY_INPUT_ID]);
// iOS Safari keeps the layout viewport and moves the visual viewport over the keyboard. The iOS app ends its web view
// at the keyboard instead, so its layout viewport shrinks and `innerHeight` is the visible height.
const SHOULD_USE_VISUAL_VIEWPORT = IS_IOS && !IS_IOS_APP;

let initialHeight = window.innerHeight;
let currentWindowSize = updateSizes();

const handleResize = throttle(() => {
  const previousHeight = currentWindowSize.height;
  currentWindowSize = updateSizes();

  if (IS_IOS_APP && currentWindowSize.height < previousHeight) {
    revealFocusedField();
  }
}, WINDOW_RESIZE_THROTTLE_MS, true);

const handleOrientationChange = throttle(() => {
  initialHeight = window.innerHeight;
  handleResize();
}, WINDOW_ORIENTATION_CHANGE_THROTTLE_MS, false);

window.addEventListener('orientationchange', handleOrientationChange);
if (SHOULD_USE_VISUAL_VIEWPORT) {
  window.visualViewport!.addEventListener('resize', handleResize);
} else {
  window.addEventListener('resize', handleResize);
}

export function updateSizes(): IDimensions {
  let height: number;
  if (SHOULD_USE_VISUAL_VIEWPORT) {
    height = window.visualViewport!.height + window.visualViewport!.pageTop;
  } else {
    height = window.innerHeight;
  }

  requestMutation(() => {
    const vh = height * 0.01;
    document.documentElement.style.setProperty('--vh', `${vh}px`);
  });

  return {
    width: window.innerWidth,
    height: window.innerHeight,
  };
}

// WebKit does not pan the page of the iOS app, so the field that opened the keyboard scrolls into view within its own
// scroller when the keyboard covers it
function revealFocusedField() {
  const field = document.activeElement;
  if (!checkIsTextField(field) || COMPOSER_INPUT_IDS.has(field.id)) return;

  requestMeasure(() => {
    const scroller = findScrollableAncestor(field);
    if (!scroller) return;

    const visibleBottom = Math.min(scroller.getBoundingClientRect().bottom, window.innerHeight);
    const distance = field.getBoundingClientRect().bottom + FOCUSED_FIELD_MARGIN - visibleBottom;
    if (distance <= 0) return;

    requestMutation(() => {
      scroller.scrollTop += distance;
    });
  });
}

function checkIsTextField(element: Element | null): element is HTMLElement {
  return element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement
    || (element instanceof HTMLElement && element.isContentEditable);
}

function findScrollableAncestor(element: HTMLElement) {
  for (let parent = element.parentElement; parent; parent = parent.parentElement) {
    const { overflowY } = getComputedStyle(parent);
    if ((overflowY === 'auto' || overflowY === 'scroll') && parent.scrollHeight > parent.clientHeight) {
      return parent;
    }
  }

  return undefined;
}

const windowSize = {
  get: () => currentWindowSize,
  getIsKeyboardVisible: () => initialHeight > currentWindowSize.height,
};

export default windowSize;
