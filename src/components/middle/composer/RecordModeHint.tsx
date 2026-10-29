import { memo, useEffect } from '../../../lib/teact/teact';

import useCurrentOrPrev from '../../../hooks/useCurrentOrPrev';
import useLang from '../../../hooks/useLang';
import useShowTransition from '../../../hooks/useShowTransition';

import styles from './RecordModeHint.module.scss';

export type RecordModeHintKey = 'LiquidRecordHoldVoice' | 'LiquidRecordHoldVideo'
  | 'LiquidRecordHoldVoiceOnly' | 'LiquidRecordHoldVideoOnly';

type OwnProps = {
  // Each new object shows the hint for the full duration again
  hint?: { key: RecordModeHintKey };
  onHide: NoneToVoidFunction;
};

const DURATION_MS = 2500;

// Says above the record button that holding it records and a tap switches between voice and video, as Telegram does
const RecordModeHint = ({ hint, onHide }: OwnProps) => {
  const lang = useLang();
  const { ref, shouldRender } = useShowTransition({ isOpen: Boolean(hint), withShouldRender: true });
  const renderedHint = useCurrentOrPrev(hint);

  useEffect(() => {
    if (!hint) return undefined;

    const timeout = window.setTimeout(onHide, DURATION_MS);
    return () => window.clearTimeout(timeout);
  }, [hint, onHide]);

  if (!shouldRender || !renderedHint) return undefined;

  return (
    <div ref={ref} className={styles.root} role="status">
      {lang(renderedHint.key)}
    </div>
  );
};

export default memo(RecordModeHint);
