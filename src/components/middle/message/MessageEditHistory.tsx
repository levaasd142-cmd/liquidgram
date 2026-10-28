import { memo } from '../../../lib/teact/teact';

import type { LiquidEditVersion } from '../../../types';

import { formatDateTime, secondsToDate } from '../../../util/localization/dateFormat';
import { renderTextWithEntities } from '../../common/helpers/renderTextWithEntities';

import useLang from '../../../hooks/useLang';

import styles from './MessageEditHistory.module.scss';

type OwnProps = {
  versions: LiquidEditVersion[];
};

const MessageEditHistory = ({ versions }: OwnProps) => {
  const lang = useLang();

  return (
    <div className={styles.root} data-ignore-on-paste>
      <div className={styles.title}>{lang('LiquidEditHistoryTitle')}</div>
      {versions.map((version) => (
        <div key={version.date} className={styles.version}>
          <div className={styles.text} dir="auto">
            {version.text?.text
              ? renderTextWithEntities({ text: version.text.text, entities: version.text.entities })
              : lang('LiquidEditHistoryEmpty')}
          </div>
          <div className={styles.date}>
            {formatDateTime(lang, secondsToDate(version.date), { date: 'short', time: 'long' })}
          </div>
        </div>
      ))}
    </div>
  );
};

export default memo(MessageEditHistory);
