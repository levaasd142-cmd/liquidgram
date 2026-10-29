import { useRef, useUnmountCleanup } from '../lib/teact/teact';

import useLastCallback from './useLastCallback';

const DEFAULT_THRESHOLD = 250;
// A touch that moves further is a swipe or a scroll, which neither clicks nor long-presses
const MOVE_TOLERANCE = 10;
// Browsers follow a tap with compatibility mouse events, which must not press a second time
const TOUCH_MOUSE_EVENTS_DELAY = 1000;

function useLongPress({
  onClick, onStart, onEnd, threshold = DEFAULT_THRESHOLD,
}: {
  onStart?: NoneToVoidFunction;
  onClick?: (event: React.MouseEvent | React.TouchEvent) => void;
  onEnd?: NoneToVoidFunction;
  threshold?: number;
}) {
  const isLongPressActiveRef = useRef(false);
  const isPressedRef = useRef(false);
  const timerIdRef = useRef<number | undefined>(undefined);
  const touchStartRef = useRef<{ x: number; y: number } | undefined>(undefined);
  const lastTouchTimeRef = useRef(0);

  const start = useLastCallback((e: React.MouseEvent | React.TouchEvent) => {
    const isTouch = 'touches' in e;
    if (isTouch) {
      lastTouchTimeRef.current = Date.now();
    } else if (Date.now() - lastTouchTimeRef.current < TOUCH_MOUSE_EVENTS_DELAY) {
      return;
    }

    const canProcessEvent = ('button' in e && e.button === 0) || (isTouch && e.touches.length > 0);
    if (isPressedRef.current || !canProcessEvent) {
      return;
    }

    isPressedRef.current = true;
    touchStartRef.current = isTouch ? { x: e.touches[0].clientX, y: e.touches[0].clientY } : undefined;
    timerIdRef.current = window.setTimeout(() => {
      onStart?.();
      isLongPressActiveRef.current = true;
    }, threshold);
  });

  const end = useLastCallback((e: React.MouseEvent | React.TouchEvent) => {
    if ('touches' in e) {
      lastTouchTimeRef.current = Date.now();
    }
    if (!isPressedRef.current) return;

    if (isLongPressActiveRef.current) {
      onEnd?.();
    } else {
      onClick?.(e);
    }

    cancel();
  });

  // Before the long press starts, moving the finger away cancels both the click and the long press
  const move = useLastCallback((e: React.TouchEvent) => {
    const startPoint = touchStartRef.current;
    const touch = e.touches[0];
    if (!isPressedRef.current || isLongPressActiveRef.current || !startPoint || !touch) return;

    if (Math.hypot(touch.clientX - startPoint.x, touch.clientY - startPoint.y) > MOVE_TOLERANCE) {
      cancel();
    }
  });

  const cancel = useLastCallback(() => {
    isLongPressActiveRef.current = false;
    isPressedRef.current = false;
    window.clearTimeout(timerIdRef.current);
  });

  // The system took the touch, such as for a gesture of its own: there is no click, but a long press still ends
  const cancelTouch = useLastCallback(() => {
    if (isLongPressActiveRef.current) {
      onEnd?.();
    }

    cancel();
  });

  useUnmountCleanup(() => {
    window.clearTimeout(timerIdRef.current);
  });

  return {
    onMouseDown: start,
    onMouseUp: end,
    onMouseLeave: end,
    onTouchStart: start,
    onTouchMove: move,
    onTouchEnd: end,
    onTouchCancel: cancelTouch,
  };
}

export default useLongPress;
