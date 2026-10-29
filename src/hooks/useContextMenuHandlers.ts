import type { ElementRef } from '../lib/teact/teact';
import { useEffect, useState } from '../lib/teact/teact';
import { addExtraClass, removeExtraClass } from '../lib/teact/teact-dom';

import type { IAnchorPosition } from '../types';
import type { Signal } from '../util/signals';

import { requestMutation } from '../lib/fasterdom/fasterdom';
import { IS_IOS, IS_IOS_APP, IS_PWA, IS_TOUCH_ENV } from '../util/browser/windowEnvironment';
import { claimTouch } from '../util/captureEvents';
import { triggerHaptic } from '../util/nativeApp';
import { removeAllSelections } from '../util/selection';
import useLastCallback from './useLastCallback';

// The iOS app waits about as long as the context menus of iOS, so a slightly slow tap stays a tap
const LONG_TAP_DURATION_MS = IS_IOS_APP ? 400 : 200;
// iOS reports every tiny move of a resting finger; `UILongPressGestureRecognizer` allows 10 pt of them
const LONG_TAP_MOVE_TOLERANCE = 10;
// WebKit on iOS clicks where a long press started once the finger lifts, if the page has no link previews: in
// home-screen web apps and in the iOS app, whose web view turns them off. For a while after the long press, mouse
// events near that point are this click, which would hit the menu.
const HAS_LONG_TAP_CLICK_THROUGH = IS_IOS && IS_PWA;
const CLICK_THROUGH_GUARD_MS = 600;
const CLICK_THROUGH_RADIUS = 24;

// One emulated context menu per touch, shared by all hooks, so nested and overlapping elements open only one
let isLongTapHandled = false;
let clickThroughGuard: { x: number; y: number; until: number } | undefined;
// The element whose long press opened a menu in the iOS app, which keeps text unselected until the next touch
let longTapElement: HTMLElement | undefined;

function stopEvent(e: Event) {
  e.stopImmediatePropagation();
  e.preventDefault();
  e.stopPropagation();
}

function handleTouchStartCapture(e: TouchEvent) {
  // A new first finger means that the previous touch ended, even if its `touchend` never reached the document
  if (e.touches.length === 1) {
    isLongTapHandled = false;
    clickThroughGuard = undefined;
    releaseLongTapSelection();
  }
}

// The touch that opened a menu must not click the element under it
function handleTouchEndCapture(e: TouchEvent) {
  if (!isLongTapHandled || e.touches.length) return;

  isLongTapHandled = false;
  // A cancelled touch clicks nothing, and its event cannot be cancelled
  if (e.type === 'touchend') stopEvent(e);
  if (clickThroughGuard) clickThroughGuard.until = performance.now() + CLICK_THROUGH_GUARD_MS;
}

function handleMouseCapture(e: MouseEvent) {
  const guard = clickThroughGuard;
  if (!guard || !e.isTrusted) return;

  if (performance.now() > guard.until) {
    clickThroughGuard = undefined;
    return;
  }

  if (Math.hypot(e.clientX - guard.x, e.clientY - guard.y) > CLICK_THROUGH_RADIUS) return;

  if (e.type === 'click') clickThroughGuard = undefined;
  stopEvent(e);
}

// A long press opens the menu without selecting text, as in Telegram for iOS. WebKit selects the text under a finger
// that rests for half a second, a moment after the menu opens, and the menu would then offer to quote it.
function preventLongTapSelection(element: HTMLElement) {
  longTapElement = element;
  document.addEventListener('selectionchange', handleLongTapSelectionChange);
  requestMutation(() => {
    addExtraClass(element, 'no-selection');
  });
}

function releaseLongTapSelection() {
  const element = longTapElement;
  if (!element) return;

  longTapElement = undefined;
  document.removeEventListener('selectionchange', handleLongTapSelectionChange);
  requestMutation(() => {
    removeExtraClass(element, 'no-selection');
  });
}

function handleLongTapSelectionChange() {
  if (window.getSelection()?.type === 'Range') {
    removeAllSelections();
  }
}

if (IS_TOUCH_ENV) {
  document.addEventListener('touchstart', handleTouchStartCapture, { capture: true, passive: true });
  document.addEventListener('touchend', handleTouchEndCapture, true);
  document.addEventListener('touchcancel', handleTouchEndCapture, true);

  if (HAS_LONG_TAP_CLICK_THROUGH) {
    document.addEventListener('mousedown', handleMouseCapture, true);
    document.addEventListener('click', handleMouseCapture, true);
  }
}

function isNativeLinkTarget(target: EventTarget | undefined) {
  if (!(target instanceof HTMLElement)) {
    return false;
  }

  const link = target.closest('a[href]');

  return Boolean(link && link.getAttribute('href') !== '#');
}

const useContextMenuHandlers = (
  elementRef: ElementRef<HTMLElement>,
  isMenuDisabled?: boolean,
  shouldDisableOnLink?: boolean,
  shouldDisableOnLongTap?: boolean,
  getIsReady?: Signal<boolean>,
  shouldDisablePropagation?: boolean,
) => {
  const [isContextMenuOpen, setIsContextMenuOpen] = useState(false);
  const [contextMenuAnchor, setContextMenuAnchor] = useState<IAnchorPosition | undefined>(undefined);
  const [contextMenuTarget, setContextMenuTarget] = useState<HTMLElement | undefined>(undefined);
  const [isContextMenuAltKeyPressed, setIsContextMenuAltKeyPressed] = useState(false);

  const handleBeforeContextMenu = useLastCallback((e: React.MouseEvent) => {
    if (!isMenuDisabled && e.button === 2) {
      requestMutation(() => {
        addExtraClass(e.target as HTMLElement, 'no-selection');
      });
    }
  });

  const handleContextMenu = useLastCallback((e: React.MouseEvent) => {
    requestMutation(() => {
      removeExtraClass(e.target as HTMLElement, 'no-selection');
    });

    if (isMenuDisabled || (shouldDisableOnLink && isNativeLinkTarget(e.target))) {
      return;
    }
    e.preventDefault();
    e.stopPropagation();

    if (contextMenuAnchor) {
      return;
    }

    setIsContextMenuAltKeyPressed(e.altKey);
    setIsContextMenuOpen(true);
    setContextMenuAnchor({ x: e.clientX, y: e.clientY });
    setContextMenuTarget(e.target as HTMLElement);
  });

  const handleContextMenuClose = useLastCallback(() => {
    setIsContextMenuOpen(false);
  });

  const handleContextMenuHide = useLastCallback(() => {
    setContextMenuAnchor(undefined);
  });

  // Support context menu on touch devices
  useEffect(() => {
    if (isMenuDisabled || !IS_TOUCH_ENV || shouldDisableOnLongTap || (getIsReady && !getIsReady())) {
      return undefined;
    }

    const element = elementRef.current;
    if (!element) {
      return undefined;
    }

    let timer: number | undefined;
    let startX = 0;
    let startY = 0;

    const clearLongPressTimer = () => {
      if (timer) {
        clearTimeout(timer);
        timer = undefined;
        document.removeEventListener('scroll', clearLongPressTimer, true);
      }
    };

    const emulateContextMenuEvent = (originalEvent: TouchEvent) => {
      clearLongPressTimer();

      const { clientX, clientY, target } = originalEvent.touches[0];

      if (contextMenuAnchor || isLongTapHandled || (shouldDisableOnLink && isNativeLinkTarget(target))) {
        return;
      }

      isLongTapHandled = true;
      clickThroughGuard = { x: clientX, y: clientY, until: Infinity };
      // Swipes, such as the swipe back, leave this touch to the menu
      claimTouch(element);
      if (IS_IOS_APP) preventLongTapSelection(element);

      triggerHaptic('medium');
      setIsContextMenuAltKeyPressed(false);
      setIsContextMenuOpen(true);
      setContextMenuAnchor({ x: clientX, y: clientY });
      setContextMenuTarget(target as HTMLElement);
    };

    const startLongPressTimer = (e: TouchEvent) => {
      if (shouldDisablePropagation) e.stopPropagation();
      clearLongPressTimer();
      if (e.touches.length !== 1) return;

      startX = e.touches[0].clientX;
      startY = e.touches[0].clientY;
      timer = window.setTimeout(() => emulateContextMenuEvent(e), LONG_TAP_DURATION_MS);
      // A list that scrolls under the finger is not a long press
      document.addEventListener('scroll', clearLongPressTimer, { capture: true, passive: true });
    };

    const handleTouchMove = (e: TouchEvent) => {
      const touch = e.touches[0];
      if (!timer || !touch) return;

      if (e.touches.length > 1
        || Math.hypot(touch.clientX - startX, touch.clientY - startY) > LONG_TAP_MOVE_TOLERANCE) {
        clearLongPressTimer();
      }
    };

    // @perf Consider event delegation
    element.addEventListener('touchstart', startLongPressTimer, { passive: true });
    element.addEventListener('touchcancel', clearLongPressTimer, true);
    element.addEventListener('touchend', clearLongPressTimer, true);
    element.addEventListener('touchmove', handleTouchMove, { passive: true });

    return () => {
      clearLongPressTimer();
      element.removeEventListener('touchstart', startLongPressTimer);
      element.removeEventListener('touchcancel', clearLongPressTimer, true);
      element.removeEventListener('touchend', clearLongPressTimer, true);
      element.removeEventListener('touchmove', handleTouchMove);
    };
  }, [
    contextMenuAnchor, isMenuDisabled, shouldDisableOnLongTap, elementRef, shouldDisableOnLink, getIsReady,
    shouldDisablePropagation,
  ]);

  return {
    isContextMenuOpen,
    contextMenuAnchor,
    contextMenuTarget,
    isContextMenuAltKeyPressed,
    handleBeforeContextMenu,
    handleContextMenu,
    handleContextMenuClose,
    handleContextMenuHide,
  };
};

export default useContextMenuHandlers;
