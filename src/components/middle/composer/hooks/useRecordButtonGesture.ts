import type { ElementRef } from '../../../../lib/teact/teact';
import { useEffect, useRef, useSignal, useState, useUnmountCleanup } from '../../../../lib/teact/teact';

import useLastCallback from '../../../../hooks/useLastCallback';

// The center of the record button in viewport coordinates when the finger went down
export type RecordHoldAnchor = {
  x: number;
  y: number;
};

// How far the finger moved left (`x`) and up (`y`) from where it went down, in pixels, so both are never positive
export type RecordHoldOffset = {
  x: number;
  y: number;
  cancelProgress: number;
  lockProgress: number;
};

type GestureOutcome = 'tap' | 'cancel' | 'lock' | 'release';

type TouchSample = {
  time: number;
  x: number;
  y: number;
};

type Gesture = {
  button: HTMLElement;
  touchId: number;
  startX: number;
  startY: number;
  x: number;
  y: number;
  samples: TouchSample[];
  anchor: RecordHoldAnchor;
  isHolding: boolean;
  holdTimer?: number;
};

// The gesture and the thresholds of the record button of Telegram for iOS (`TGModernConversationInputMicButton` and
// `ChatTextInputMediaRecordingButton`): a finger that stays down records, a tap does not
const HOLD_DELAY_MS = 190;
// Telegram ignores a touch that starts sooner after the last one it handled
const REPEATED_TOUCH_INTERVAL_MS = 400;
// Moving this far left or up cancels or locks the recording at once
const CANCEL_DISTANCE = 150;
const LOCK_DISTANCE = 110;
// Lifting the finger after moving this far, or with a fling, cancels or locks it too
const RELEASE_CANCEL_DISTANCE = 100;
const RELEASE_LOCK_DISTANCE = 60;
const FLING_VELOCITY = 400; // px per second
// Telegram measures a fling with a pan, which starts only after the finger moved this far, so a tap never flings
const FLING_MIN_DISTANCE = 10;
// The lock badge closes over this distance
const LOCK_PROGRESS_DISTANCE = 105;
const VELOCITY_WINDOW_MS = 100;
const MS_IN_SECOND = 1000;
// WebKit can click the button after a long press it did not hand to the page, which must not record again
const CLICK_SUPPRESSION_MS = 400;

export default function useRecordButtonGesture({
  buttonRef,
  isEnabled,
  onTap,
  onHoldStart,
  onCancel,
  onLock,
  onRelease,
}: {
  buttonRef: ElementRef<HTMLElement>;
  isEnabled: boolean;
  onTap: NoneToVoidFunction;
  // Starts a recording and returns whether the finger now holds it, rather than another screen taking over
  onHoldStart: () => boolean;
  onCancel: NoneToVoidFunction;
  onLock: NoneToVoidFunction;
  onRelease: NoneToVoidFunction;
}) {
  const [holdAnchor, setHoldAnchor] = useState<RecordHoldAnchor | undefined>();
  const [getHoldOffset, setHoldOffset] = useSignal<RecordHoldOffset | undefined>();
  const gestureRef = useRef<Gesture>();
  const lastHandledTouchAtRef = useRef(0);
  const lastGestureEndAtRef = useRef(0);

  const finishGesture = useLastCallback((outcome?: GestureOutcome) => {
    const gesture = gestureRef.current;
    if (!gesture) return;

    gestureRef.current = undefined;
    lastGestureEndAtRef.current = Date.now();
    window.clearTimeout(gesture.holdTimer);
    gesture.button.removeEventListener('touchmove', handleTouchMove);
    gesture.button.removeEventListener('touchend', handleTouchEnd);
    gesture.button.removeEventListener('touchcancel', handleTouchCancel);

    if (gesture.isHolding) {
      setHoldAnchor(undefined);
      setHoldOffset(undefined);
    }

    switch (outcome) {
      case 'tap':
        onTap();
        break;
      case 'cancel':
        onCancel();
        break;
      case 'lock':
        onLock();
        break;
      case 'release':
        onRelease();
        break;
    }
  });

  const startHolding = useLastCallback((gesture: Gesture) => {
    window.clearTimeout(gesture.holdTimer);
    gesture.holdTimer = undefined;
    if (!onHoldStart()) return false;

    gesture.isHolding = true;
    setHoldAnchor(gesture.anchor);
    publishOffset(gesture);
    return true;
  });

  const handleHoldTimeout = useLastCallback(() => {
    const gesture = gestureRef.current;
    if (!gesture) return;

    if (!startHolding(gesture)) {
      finishGesture();
    }
  });

  // Telegram counts a flick up from the button as holding it and locking at once
  const lockRightAway = useLastCallback((gesture: Gesture) => {
    finishGesture(gesture.isHolding || startHolding(gesture) ? 'lock' : undefined);
  });

  const handleTouchStart = useLastCallback((e: TouchEvent) => {
    // The gesture decides what the touch does: iOS would click the button when the finger lifts, and select text or
    // scroll the page while it moves
    e.preventDefault();
    if (gestureRef.current || e.touches.length > 1) return;

    const now = Date.now();
    if (now - lastHandledTouchAtRef.current < REPEATED_TOUCH_INTERVAL_MS) return;
    lastHandledTouchAtRef.current = now;

    const button = e.currentTarget as HTMLElement;
    const touch = e.changedTouches[0];
    const rect = button.getBoundingClientRect();
    const gesture: Gesture = {
      button,
      touchId: touch.identifier,
      startX: touch.clientX,
      startY: touch.clientY,
      x: 0,
      y: 0,
      samples: [{ time: e.timeStamp, x: touch.clientX, y: touch.clientY }],
      anchor: { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 },
      isHolding: false,
    };
    gesture.holdTimer = window.setTimeout(handleHoldTimeout, HOLD_DELAY_MS);
    gestureRef.current = gesture;

    button.addEventListener('touchmove', handleTouchMove, { passive: false });
    button.addEventListener('touchend', handleTouchEnd);
    button.addEventListener('touchcancel', handleTouchCancel);
  });

  const handleTouchMove = useLastCallback((e: TouchEvent) => {
    const gesture = gestureRef.current;
    const touch = gesture && findTouch(e.changedTouches, gesture.touchId);
    if (!touch) return;

    e.preventDefault();
    trackTouch(gesture, touch, e.timeStamp);

    if (gesture.x < -CANCEL_DISTANCE) {
      finishGesture(gesture.isHolding ? 'cancel' : undefined);
    } else if (gesture.y < -LOCK_DISTANCE) {
      lockRightAway(gesture);
    } else if (gesture.isHolding) {
      publishOffset(gesture);
    }
  });

  const handleTouchEnd = useLastCallback((e: TouchEvent) => {
    const gesture = gestureRef.current;
    const touch = gesture && findTouch(e.changedTouches, gesture.touchId);
    if (!touch) return;

    trackTouch(gesture, touch, e.timeStamp);
    const velocity = Math.hypot(gesture.x, gesture.y) > FLING_MIN_DISTANCE ? getVelocity(gesture.samples) : undefined;
    // Like Telegram, a release counts along the axis the finger moved most, and a fling counts on its own
    const isHorizontal = Math.abs(gesture.x) > Math.abs(gesture.y);
    const isCancel = (velocity && velocity.x < -FLING_VELOCITY)
      || (isHorizontal && gesture.x < -RELEASE_CANCEL_DISTANCE);
    const isLock = (velocity && velocity.y < -FLING_VELOCITY)
      || (!isHorizontal && gesture.y < -RELEASE_LOCK_DISTANCE);

    if (isCancel) {
      finishGesture(gesture.isHolding ? 'cancel' : undefined);
    } else if (isLock) {
      lockRightAway(gesture);
    } else {
      finishGesture(gesture.isHolding ? 'release' : 'tap');
    }
  });

  const handleTouchCancel = useLastCallback((e: TouchEvent) => {
    const gesture = gestureRef.current;
    if (!gesture || !findTouch(e.changedTouches, gesture.touchId)) return;

    // A system alert, such as the one asking for the microphone, took the touch: like Telegram, the recording goes on
    finishGesture(gesture.isHolding ? 'lock' : undefined);
  });

  function publishOffset(gesture: Gesture) {
    setHoldOffset({
      x: gesture.x,
      y: gesture.y,
      cancelProgress: Math.min(1, -gesture.x / CANCEL_DISTANCE),
      lockProgress: Math.min(1, -gesture.y / LOCK_PROGRESS_DISTANCE),
    });
  }

  useEffect(() => {
    const button = buttonRef.current;
    if (!isEnabled || !button) return undefined;

    button.addEventListener('touchstart', handleTouchStart, { passive: false });
    return () => {
      button.removeEventListener('touchstart', handleTouchStart);
    };
  }, [buttonRef, isEnabled, handleTouchStart]);

  useUnmountCleanup(() => {
    finishGesture();
  });

  const getIsClickSuppressed = useLastCallback(() => Date.now() - lastGestureEndAtRef.current < CLICK_SUPPRESSION_MS);

  // Ends the gesture without an outcome, for a recording that could not start
  const abortHold = useLastCallback(() => {
    if (gestureRef.current?.isHolding) {
      finishGesture();
    }
  });

  return {
    holdAnchor,
    getHoldOffset,
    getIsClickSuppressed,
    abortHold,
  };
}

function findTouch(touches: TouchList, id: number) {
  for (let i = 0; i < touches.length; i++) {
    if (touches[i].identifier === id) return touches[i];
  }

  return undefined;
}

function trackTouch(gesture: Gesture, touch: Touch, time: number) {
  gesture.x = Math.min(0, touch.clientX - gesture.startX);
  gesture.y = Math.min(0, touch.clientY - gesture.startY);

  const { samples } = gesture;
  samples.push({ time, x: touch.clientX, y: touch.clientY });
  while (samples.length > 2 && time - samples[0].time > VELOCITY_WINDOW_MS) {
    samples.shift();
  }
}

function getVelocity(samples: TouchSample[]) {
  const first = samples[0];
  const last = samples[samples.length - 1];
  const duration = last.time - first.time;
  if (duration <= 0) return { x: 0, y: 0 };

  return {
    x: ((last.x - first.x) / duration) * MS_IN_SECOND,
    y: ((last.y - first.y) / duration) * MS_IN_SECOND,
  };
}
