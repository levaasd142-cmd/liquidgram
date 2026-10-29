import type { MoveOffsets } from './captureEvents';

import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import { IS_IOS, IS_IOS_APP } from './browser/windowEnvironment';
import { animateNumber, timingFunctions } from './animation';
import { captureEvents, SwipeDirection } from './captureEvents';
import { waitForAnimationEnd } from './cssAnimationEndListeners';
import { clamp } from './math';

const INERTIA_DURATION = 300;
const INERTIA_EASING = timingFunctions.easeOutCubic;
// A release past this share of the way completes a swipe, and so does a flick forward at this speed in px/ms. A flick
// back at the same speed cancels it.
const COMPLETE_PROGRESS = 0.4;
const FLICK_VELOCITY = 0.35;
// The speed of a release comes from the moves of this last stretch of time, so a finger that rested has none
const VELOCITY_WINDOW_MS = 100;
const TRANSLATE_REGEX = /translate(X|Y|3d)?\(([^)]*)\)/;
const TRANSLATE_VALUE_REGEX = /^(-?[\d.]+)(%|px)?$/;

let isSwipeActive = false;
let swipeOffsets: MoveOffsets | undefined;
let onDrag: ((offsets: MoveOffsets) => void) | undefined;
let onRelease: ((onCancel: NoneToVoidFunction, shouldComplete?: boolean) => void) | undefined;
let cancelCurrentReleaseAnimation: NoneToVoidFunction | undefined;

export function captureControlledSwipe(
  element: HTMLElement, options: {
    excludedClosestSelector?: string;
    selectorToPreventScroll?: string;
    onSwipeLeftStart?: NoneToVoidFunction;
    onSwipeRightStart?: NoneToVoidFunction;
    // Leaves the swipe to other handlers, such as the chat folders, when there is nothing to go back to
    getCanSwipeRight?: () => boolean;
    onCancel: NoneToVoidFunction;
  },
) {
  // The iOS app decides like its other back swipes, by the distance and the speed of the release
  const velocityTracker = IS_IOS_APP ? createVelocityTracker() : undefined;
  let forwardSign = 1;

  return captureEvents(element, {
    excludedClosestSelector: options.excludedClosestSelector,
    selectorToPreventScroll: options.selectorToPreventScroll,
    swipeThreshold: 10,

    onSwipe(e, direction, offsets) {
      if (direction === SwipeDirection.Left) {
        options.onSwipeLeftStart?.();
        forwardSign = -1;
      } else if (direction === SwipeDirection.Right) {
        if (options.getCanSwipeRight && !options.getCanSwipeRight()) return false;

        options.onSwipeRightStart?.();
        forwardSign = 1;
      } else {
        return false;
      }

      velocityTracker?.reset();
      velocityTracker?.add(offsets.dragOffsetX * forwardSign, e.timeStamp);
      startControlledSwipe(offsets);

      return true;
    },

    onDrag(e, captureEvent, offsets) {
      if (!isSwipeActive) return;

      velocityTracker?.add(offsets.dragOffsetX * forwardSign, e.timeStamp);
      dragControlledSwipe(offsets);
    },

    onRelease(e) {
      if (!isSwipeActive || !swipeOffsets) return;

      const shouldComplete = velocityTracker ? getShouldCompleteSwipe(
        (velocityTracker.getLastValue() - swipeOffsets.dragOffsetX * forwardSign) / element.offsetWidth,
        velocityTracker.getVelocity(e.timeStamp),
      ) : undefined;
      releaseControlledSwipe(options.onCancel, shouldComplete);
    },
  });
}

// Makes the next transition with swipe control follow the finger, starting from these offsets of the touch.
// Transitions follow the finger on iOS only.
export function startControlledSwipe(offsets: MoveOffsets) {
  if (!IS_IOS) return;

  isSwipeActive = true;
  swipeOffsets = offsets;
}

export function dragControlledSwipe(offsets: MoveOffsets) {
  if (!isSwipeActive) return;

  onDrag?.(offsets);
}

// Plays the rest of the transition, or reverts it and calls `onCancel`. Without `shouldComplete`, the direction of the
// last move decides.
export function releaseControlledSwipe(onCancel: NoneToVoidFunction, shouldComplete?: boolean) {
  if (!isSwipeActive) return;

  isSwipeActive = false;

  onRelease?.(onCancel, shouldComplete);

  onDrag = undefined;
  onRelease = undefined;
}

export function getShouldCompleteSwipe(progress: number, velocity: number) {
  if (velocity >= FLICK_VELOCITY) return true;
  if (velocity <= -FLICK_VELOCITY) return false;

  return progress >= COMPLETE_PROGRESS;
}

// Measures how fast a value, such as the offset of a finger, changed over its last updates, in units per ms. The times
// are those of the events, so a busy page that handles a burst of late events still sees the pace of the finger.
export function createVelocityTracker() {
  let samples: { time: number; value: number }[] = [];

  return {
    add(value: number, time: number) {
      samples.push({ time, value });
      samples = samples.filter((sample) => time - sample.time <= VELOCITY_WINDOW_MS);
    },
    getVelocity(time: number) {
      const recentSamples = samples.filter((sample) => time - sample.time <= VELOCITY_WINDOW_MS);
      if (recentSamples.length < 2) return 0;

      const first = recentSamples[0];
      const last = recentSamples[recentSamples.length - 1];
      return (last.value - first.value) / Math.max(1, last.time - first.time);
    },
    getLastValue() {
      return samples.length ? samples[samples.length - 1].value : 0;
    },
    reset() {
      samples = [];
    },
  };
}

export function allowSwipeControlForTransition(
  currentSlide: HTMLElement,
  nextSlide: HTMLElement,
  onCancelForTransition: NoneToVoidFunction,
) {
  cancelCurrentReleaseAnimation?.();

  if (!isSwipeActive) return;

  const targetPosition = extractAnimationEndPosition(currentSlide);
  if (!targetPosition) return;

  currentSlide.getAnimations().forEach((a) => a.pause());
  nextSlide.getAnimations().forEach((a) => a.pause());

  currentSlide.style.animationTimingFunction = 'linear';
  nextSlide.style.animationTimingFunction = 'linear';

  let currentDirection: 1 | -1 | undefined;

  requestMeasure(() => {
    const computedStyle = getComputedStyle(currentSlide);
    const initialPositionPx = extractPositionFromMatrix(computedStyle.transform, targetPosition.axis);
    const targetPositionPx = targetPosition.units === 'px'
      ? targetPosition.value
      : ((targetPosition.value / 100) * (
        targetPosition.axis === 'X' ? currentSlide.offsetWidth : currentSlide.offsetHeight
      ));
    const distance = targetPositionPx - initialPositionPx;

    let progress = 0;

    onDrag = ({ dragOffsetX, dragOffsetY }) => {
      const dragOffset = targetPosition.axis === 'X'
        ? dragOffsetX - swipeOffsets!.dragOffsetX
        : dragOffsetY - swipeOffsets!.dragOffsetY;

      const newProgress = clamp(dragOffset / distance, 0, 1);
      currentDirection = newProgress > progress ? 1 : -1;
      progress = newProgress;

      updateAnimationProgress([currentSlide, nextSlide], progress);
    };

    onRelease = (onCancelForClient: NoneToVoidFunction, shouldComplete?: boolean) => {
      const isRevertSwipe = shouldComplete !== undefined ? !shouldComplete : currentDirection === -1;

      function cleanup() {
        currentSlide.getAnimations().forEach((a) => a.cancel());
        nextSlide.getAnimations().forEach((a) => a.cancel());

        requestMutation(() => {
          currentSlide.style.animationTimingFunction = '';
          nextSlide.style.animationTimingFunction = '';
        });
      }

      if (!isRevertSwipe) {
        // For some reason animations are not cleared when CSS class is removed
        waitForAnimationEnd(currentSlide, cleanup);
      }

      cancelCurrentReleaseAnimation = animateNumber({
        from: progress,
        to: isRevertSwipe ? 0 : 1,
        duration: INERTIA_DURATION,
        timing: INERTIA_EASING,
        onUpdate(releaseProgress) {
          updateAnimationProgress([currentSlide, nextSlide], releaseProgress);
        },
        onEnd(isCanceled = false) {
          cancelCurrentReleaseAnimation = undefined;

          if (isCanceled || isRevertSwipe) {
            cleanup();
            onCancelForTransition();
            onCancelForClient();
          }
        },
      });
    };
  });
}

function updateAnimationProgress(elements: HTMLElement[], progress: number) {
  elements.map((e) => e.getAnimations()).flat().forEach((animation) => {
    animation.currentTime = (animation.effect!.getTiming().duration as number) * progress;
  });
}

function extractAnimationEndPosition(element: HTMLElement) {
  for (const animation of element.getAnimations()) {
    if (!(animation.effect instanceof KeyframeEffect)) continue;

    for (const keyframe of animation.effect.getKeyframes()) {
      if (keyframe.offset !== 1 || !keyframe.transform) continue;

      const position = extractPositionFromTransform(keyframe.transform as string);
      if (position) {
        return position;
      }
    }
  }

  return undefined;
}

// Minified CSS writes `translateX(100%)` as `translate(100%)`, so every form of `translate` counts
function extractPositionFromTransform(transformRule: string) {
  const match = transformRule.match(TRANSLATE_REGEX);
  if (!match) return undefined;

  const [, kind, args] = match;
  const values = args.split(',').map((arg) => arg.trim().match(TRANSLATE_VALUE_REGEX));
  // `translate(x, y)` and `translate3d(x, y, z)` move along Y when x is zero
  const axis: 'X' | 'Y' = kind === 'Y' || (kind !== 'X' && Boolean(values[1]) && !Number(values[0]?.[1])) ? 'Y' : 'X';
  const value = axis === 'Y' && kind !== 'Y' ? values[1] : values[0];
  if (!value) return undefined;

  return {
    axis,
    value: Number(value[1]),
    // A zero may come without units
    units: value[2] || 'px',
  };
}

function extractPositionFromMatrix(transform: string, axis: 'X' | 'Y') {
  if (transform === 'none') return 0;

  const matrix = transform.slice(7, -1).split(',').map(Number);
  return matrix[axis === 'X' ? 4 : 5];
}
