import type { ElementRef } from '../../../lib/teact/teact';
import { useEffect } from '../../../lib/teact/teact';

import { IS_IOS_APP, IS_TOUCH_ENV } from '../../../util/browser/windowEnvironment';
import { getTouchOwner } from '../../../util/captureEvents';

// A drag down this far over the messages closes the keyboard
const DISMISS_DISTANCE = 24;
// The drag must go this many times further down than sideways
const VERTICAL_RATIO = 1.5;
const EDITABLE_SELECTOR = 'input, textarea, [contenteditable="true"]';

// In the iPhone app, dragging the messages down closes the keyboard, as in Telegram for iOS. Its web view shows the
// keyboard without the toolbar that has a Done button.
export default function useKeyboardDismissOnDrag(middleColumnRef: ElementRef<HTMLDivElement>) {
  useEffect(() => {
    if (!IS_IOS_APP || !IS_TOUCH_ENV) return undefined;

    const middleColumn = middleColumnRef.current;
    if (!middleColumn) return undefined;

    let focusedField: HTMLElement | undefined;
    let startX = 0;
    let startY = 0;

    function handleTouchStart(e: TouchEvent) {
      focusedField = undefined;
      const activeElement = document.activeElement;
      if (e.touches.length !== 1 || !(activeElement instanceof HTMLElement)
        || !middleColumn!.contains(activeElement) || !activeElement.matches(EDITABLE_SELECTOR)
        || !(e.target as HTMLElement).closest('.MessageList')) {
        return;
      }

      focusedField = activeElement;
      startX = e.touches[0].clientX;
      startY = e.touches[0].clientY;
    }

    function handleTouchMove(e: TouchEvent) {
      if (!focusedField) return;

      // Swipes to reply or back take the touch
      if (getTouchOwner()) {
        focusedField = undefined;
        return;
      }

      const offsetX = Math.abs(e.touches[0].clientX - startX);
      const offsetY = e.touches[0].clientY - startY;
      if (offsetY >= DISMISS_DISTANCE && offsetY >= offsetX * VERTICAL_RATIO) {
        focusedField.blur();
        focusedField = undefined;
      } else if (offsetX >= DISMISS_DISTANCE || -offsetY >= DISMISS_DISTANCE) {
        focusedField = undefined;
      }
    }

    middleColumn.addEventListener('touchstart', handleTouchStart, { passive: true });
    middleColumn.addEventListener('touchmove', handleTouchMove, { passive: true });

    return () => {
      middleColumn.removeEventListener('touchstart', handleTouchStart);
      middleColumn.removeEventListener('touchmove', handleTouchMove);
    };
  }, [middleColumnRef]);
}
