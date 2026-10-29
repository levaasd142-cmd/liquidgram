import { memo, useEffect } from '../../../lib/teact/teact';

import type { Signal } from '../../../util/signals';
import type { RecordHoldAnchor, RecordHoldOffset } from './hooks/useRecordButtonGesture';

import { requestMutation } from '../../../lib/fasterdom/fasterdom';

import useCurrentOrPrev from '../../../hooks/useCurrentOrPrev';
import useShowTransition from '../../../hooks/useShowTransition';
import { useSignalEffect } from '../../../hooks/useSignalEffect';

import Icon from '../../common/icons/Icon';
import Portal from '../../ui/Portal';

import styles from './RecordHoldOverlay.module.scss';

type OwnProps = {
  // Where the record button was when the finger went down; `undefined` hides the overlay
  anchor?: RecordHoldAnchor;
  isVideo?: boolean;
  getOffset: Signal<RecordHoldOffset | undefined>;
  subscribeToPeaks: (listener: (peak: number) => void) => NoneToVoidFunction;
};

// The microphone level that fills the ring around the button
const MAX_LEVEL_PEAK = 0.5;

// What a held record button shows, as in Telegram for iOS: a large button under the finger that follows it and
// shrinks while it slides to cancel, and a lock badge above it that closes while it slides up
const RecordHoldOverlay = ({
  anchor, isVideo, getOffset, subscribeToPeaks,
}: OwnProps) => {
  const { ref, shouldRender } = useShowTransition({ isOpen: Boolean(anchor), withShouldRender: true });
  const renderedAnchor = useCurrentOrPrev(anchor);

  useSignalEffect(() => {
    const offset = getOffset();
    const element = ref.current;
    if (!offset || !element) return;

    requestMutation(() => {
      element.style.setProperty('--hold-x', `${offset.x}px`);
      element.style.setProperty('--hold-y', `${offset.y}px`);
      element.style.setProperty('--hold-cancel', String(offset.cancelProgress));
      element.style.setProperty('--hold-lock', String(offset.lockProgress));
    });
  }, [getOffset, ref]);

  useEffect(() => {
    if (!shouldRender) return undefined;

    return subscribeToPeaks((peak) => {
      const element = ref.current;
      if (!element) return;

      const level = Math.min(1, peak / MAX_LEVEL_PEAK);
      requestMutation(() => {
        element.style.setProperty('--hold-level', String(level));
      });
    });
  }, [ref, shouldRender, subscribeToPeaks]);

  if (!shouldRender || !renderedAnchor) return undefined;

  return (
    <Portal>
      <div
        ref={ref}
        className={styles.root}
        style={`left: ${renderedAnchor.x}px; top: ${renderedAnchor.y}px`}
        aria-hidden
      >
        <div className={styles.lock}>
          <div className={styles.lockBadge}>
            <span className={styles.lockIcons}>
              <Icon name="unlock" className={styles.unlockIcon} />
              <Icon name="lock" className={styles.lockIcon} />
            </span>
            <Icon name="up" className={styles.lockArrow} />
          </div>
        </div>
        <div className={styles.button}>
          <div className={styles.level} />
          <div className={styles.circle}>
            <Icon name={isVideo ? 'round-video' : 'microphone'} />
          </div>
        </div>
      </div>
    </Portal>
  );
};

export default memo(RecordHoldOverlay);
