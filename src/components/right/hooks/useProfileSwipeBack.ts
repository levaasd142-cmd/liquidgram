import { useEffect } from '../../../lib/teact/teact';

import { requestMutation } from '../../../lib/fasterdom/fasterdom';
import { IS_IOS_APP, IS_TOUCH_ENV } from '../../../util/browser/windowEnvironment';
import { captureSwipeBack, settleSwipeLayers } from '../../../util/swipeBack';

import useLastCallback from '../../../hooks/useLastCallback';
import { useStateRef } from '../../../hooks/useStateRef';

// The chat under an open profile sits this share of the screen to the left, see `Main.scss`. In RTL the swipe brings
// it out from the right.
const MIDDLE_COLUMN_SHIFT = 0.2;
// The profile swipes between its media tabs at the default distance of `captureEvents`, so the back swipe takes the
// same distance and lets the tabs decide first
const SWIPE_THRESHOLD = 20;
// The layout moves the columns within a few frames after the profile closes
const LAYOUT_TIMEOUT = 1000;

// The iPhone app's swipe back from a profile to its chat: the profile follows the finger and the chat comes out from
// under it as its shade fades, as when the profile closes. RTL mirrors the direction.
export default function useProfileSwipeBack({
  isEnabled,
  isRtl,
  onBack,
}: {
  isEnabled: boolean;
  isRtl?: boolean;
  onBack: NoneToVoidFunction;
}) {
  const isEnabledRef = useStateRef(isEnabled);
  const handleBack = useLastCallback(onBack);

  useEffect(() => {
    if (!IS_IOS_APP || !IS_TOUCH_ENV) return undefined;

    const rightColumn = document.getElementById('RightColumn');
    const middleColumn = document.getElementById('MiddleColumn');
    const main = document.getElementById('Main');
    if (!rightColumn || !middleColumn || !main) return undefined;

    const direction = isRtl ? -1 : 1;
    let layers: HTMLElement[] = [];
    let backdrop: HTMLElement | undefined;
    let backdropOpacity = 0;
    let width = 0;
    let offset = 0;
    let isSwiping = false;
    let isMoveScheduled = false;

    function moveLayers(layerOffset: number) {
      const progress = layerOffset / width;
      const middleColumnOffset = -direction * MIDDLE_COLUMN_SHIFT * width * (1 - progress);
      rightColumn!.style.transform = `translate3d(${direction * layerOffset}px, 0, 0)`;
      middleColumn!.style.transform = `translate3d(${middleColumnOffset}px, 0, 0)`;
      if (backdrop) {
        backdrop.style.opacity = String(backdropOpacity * (1 - progress));
      }
    }

    function resetLayers() {
      isSwiping = false;
      const swipedLayers = layers;
      requestMutation(() => {
        swipedLayers.forEach((layer) => {
          layer.style.transition = '';
          layer.style.transform = '';
          layer.style.opacity = '';
        });
      });
    }

    // Takes off the inline styles once the profile has closed. The profile then slides on to its place off screen
    // with the layout's transition, whose end the layout waits for.
    function resetLayersAfterProfileCloses(startedAt = Date.now()) {
      if (!main!.classList.contains('right-column-open') || Date.now() - startedAt > LAYOUT_TIMEOUT) {
        resetLayers();
        return;
      }

      requestAnimationFrame(() => resetLayersAfterProfileCloses(startedAt));
    }

    const releaseSwipe = captureSwipeBack(rightColumn, {
      isRtl,
      // The photos swipe to the next one
      edgeOnlyClosestSelector: '.ProfileInfo',
      selectorToPreventScroll: '#RightColumn .custom-scroll',
      swipeThreshold: SWIPE_THRESHOLD,
      shouldYieldToInnerSwipes: true,
      getIsEnabled: () => isEnabledRef.current && !isSwiping,

      onStart() {
        isSwiping = true;
        backdrop = document.querySelector<HTMLElement>('#RightColumn-wrapper > .overlay-backdrop') || undefined;
        backdropOpacity = backdrop ? Number(getComputedStyle(backdrop).opacity) : 0;
        layers = backdrop ? [rightColumn, middleColumn, backdrop] : [rightColumn, middleColumn];
        width = rightColumn.offsetWidth;
        offset = 0;
        requestMutation(() => {
          layers.forEach((layer) => {
            layer.style.transition = 'none';
          });
        });
      },

      onMove(newOffset) {
        offset = Math.min(newOffset, width);
        if (isMoveScheduled) return;

        isMoveScheduled = true;
        requestMutation(() => {
          isMoveScheduled = false;
          if (isSwiping) moveLayers(offset);
        });
      },

      onEnd(shouldGoBack, velocity) {
        const targetOffset = shouldGoBack ? width : 0;
        settleSwipeLayers(layers, targetOffset - offset, velocity, () => moveLayers(targetOffset), () => {
          if (!shouldGoBack) {
            resetLayers();
            return;
          }

          // The layout keeps the closed profile off the right edge, so it goes there before its transition moves it on
          requestMutation(() => {
            rightColumn.style.transition = 'none';
            rightColumn.style.transform = `translate3d(${width}px, 0, 0)`;
          });
          handleBack();
          resetLayersAfterProfileCloses();
        });
      },
    });

    return () => {
      releaseSwipe();
      if (isSwiping) resetLayers();
    };
  }, [isEnabledRef, isRtl]);
}
