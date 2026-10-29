import type { RealTouchEvent } from './captureEvents';

import { requestMutation } from '../lib/fasterdom/fasterdom';
import {
  captureEvents, getIsInDragOnlyElement, getTouchOwner, IOS_SCREEN_EDGE_THRESHOLD, reserveSwipe, SwipeDirection,
} from './captureEvents';
import { clamp } from './math';
import { createVelocityTracker, getShouldCompleteSwipe } from './swipeController';
import windowSize from './windowSize';

type SwipeBackOptions = {
  isRtl?: boolean;
  // Touches here never start the swipe
  excludedClosestSelector?: string;
  // Touches here start it only at the screen edge, because these elements move sideways themselves
  edgeOnlyClosestSelector?: string;
  selectorToPreventScroll?: string;
  // In px; at least the distance at which `captureEvents` counts a touch as moved, so every swipe gets its release
  swipeThreshold?: number;
  // Lets handlers inside the element that take a swipe at the same distance decide first, on the same move. A swipe
  // from the edge is not theirs.
  shouldYieldToInnerSwipes?: boolean;
  getIsEnabled: () => boolean;
  // Returns `false` to leave the touch alone
  onStart: () => boolean | void;
  // `offset` is how far, in px, the finger moved toward going back since the swipe started
  onMove: (offset: number) => void;
  onEnd: (shouldGoBack: boolean, velocity: number) => void;
};

const SWIPE_THRESHOLD = 15;
// Lets the release of a CSS transition finish before the layers lose their inline styles
const SETTLE_END_DELAY = 34;
const SETTLE_MIN_DURATION = 120;
const SETTLE_MAX_DURATION = 320;
// px/ms; a finger that rested before lifting settles at this speed
const SETTLE_MIN_SPEED = 1;
const SETTLE_EASING = 'cubic-bezier(0.25, 0.8, 0.25, 1)';
const TEXT_EDITING_SELECTOR = 'input, textarea, [contenteditable="true"]';

// Swipe back like on iOS: a horizontal swipe away from the start edge, from the edge or from anywhere in `element`.
// The caller moves its layers in `onMove`, and `onEnd` says whether the release goes back, by its distance and speed.
// Touches on fields, on elements that drag or scroll sideways, and touches that another handler took, are left alone,
// except that the edge belongs to the back swipe, as on iOS.
export function captureSwipeBack(element: HTMLElement, options: SwipeBackOptions) {
  const backDirection = options.isRtl ? SwipeDirection.Left : SwipeDirection.Right;
  const velocityTracker = createVelocityTracker();
  let startTarget: HTMLElement | undefined;
  let isFromEdge = false;
  let hasYielded = false;
  let isActive = false;
  let startOffset = 0;
  let offset = 0;

  function getBackOffset(dragOffsetX: number) {
    return options.isRtl ? -dragOffsetX : dragOffsetX;
  }

  function getCanStartFrom(target: HTMLElement) {
    if (target.closest(TEXT_EDITING_SELECTOR)) return false;
    if (options.excludedClosestSelector && target.closest(options.excludedClosestSelector)) return false;
    if (getIsInDragOnlyElement(target, element)) return false;
    if (isFromEdge) return true;
    if (options.edgeOnlyClosestSelector && target.closest(options.edgeOnlyClosestSelector)) return false;

    return !findHorizontalScroller(target, element);
  }

  function end(shouldGoBack: boolean) {
    isActive = false;
    options.onEnd(shouldGoBack, velocityTracker.getVelocity());
  }

  return captureEvents(element, {
    swipeThreshold: options.swipeThreshold ?? SWIPE_THRESHOLD,
    selectorToPreventScroll: options.selectorToPreventScroll,
    withNativeDrag: true,

    onCapture(e) {
      if (e.type !== 'touchstart' || (e as RealTouchEvent).touches.length !== 1) {
        startTarget = undefined;
        return;
      }

      // A release that never reached the handlers still ends the previous swipe
      if (isActive) end(false);

      hasYielded = false;
      const { clientX } = (e as RealTouchEvent).touches[0];
      startTarget = e.target as HTMLElement;
      isFromEdge = options.isRtl
        ? clientX >= windowSize.get().width - IOS_SCREEN_EDGE_THRESHOLD
        : clientX <= IOS_SCREEN_EDGE_THRESHOLD;

      if (isFromEdge && options.getIsEnabled() && getCanStartFrom(startTarget)) {
        reserveSwipe(element, backDirection);
      }
    },

    onSwipe(e, direction, { dragOffsetX }) {
      if (!startTarget || direction !== backDirection || !options.getIsEnabled()) return false;

      const owner = getTouchOwner();
      if (owner && owner !== element) return false;

      if (options.shouldYieldToInnerSwipes && !isFromEdge && !hasYielded) {
        hasYielded = true;
        return false;
      }

      if (!getCanStartFrom(startTarget) || options.onStart() === false) return false;

      isActive = true;
      startOffset = getBackOffset(dragOffsetX);
      offset = 0;
      velocityTracker.reset();
      velocityTracker.add(offset);

      return true;
    },

    onDrag(e, captureEvent, { dragOffsetX }) {
      if (!isActive) return;

      offset = Math.max(0, getBackOffset(dragOffsetX) - startOffset);
      velocityTracker.add(offset);
      options.onMove(offset);
    },

    onRelease(e) {
      if (!isActive) return;

      end(e.type !== 'touchcancel' && getShouldCompleteSwipe(
        offset / element.offsetWidth, velocityTracker.getVelocity(),
      ));
    },
  });
}

// Plays the rest of a swipe back with CSS transitions: `applyStyles` sets the final styles of `elements`
export function settleSwipeLayers(
  elements: HTMLElement[],
  distance: number,
  velocity: number,
  applyStyles: NoneToVoidFunction,
  onSettled: NoneToVoidFunction,
) {
  const duration = clamp(
    Math.abs(distance) / Math.max(Math.abs(velocity), SETTLE_MIN_SPEED),
    SETTLE_MIN_DURATION,
    SETTLE_MAX_DURATION,
  );

  requestMutation(() => {
    elements.forEach((layer) => {
      layer.style.transition = `transform ${duration}ms ${SETTLE_EASING}, opacity ${duration}ms ${SETTLE_EASING}`;
    });
    applyStyles();
  });

  window.setTimeout(onSettled, duration + SETTLE_END_DELAY);
}

function findHorizontalScroller(target: HTMLElement, root: HTMLElement) {
  for (let element: HTMLElement | null = target; element && element !== root; element = element.parentElement) {
    if (element.scrollWidth > element.clientWidth) {
      const { overflowX } = getComputedStyle(element);
      if (overflowX === 'auto' || overflowX === 'scroll') return element;
    }
  }

  return undefined;
}
