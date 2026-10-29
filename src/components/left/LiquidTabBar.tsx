import { memo } from '../../lib/teact/teact';
import { getActions, withGlobal } from '../../global';

import type { IconName } from '../../types/icons';
import type { RegularLangKey } from '../../types/language';
import { LeftColumnContent, SettingsScreens } from '../../types';

import { selectCurrentMessageList, selectTabState } from '../../global/selectors';
import { selectLiquidSettings } from '../../global/selectors/sharedState';
import buildClassName from '../../util/buildClassName';

import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import Icon from '../common/icons/Icon';

import styles from './LiquidTabBar.module.scss';

type OwnProps = {
  isMobile?: boolean;
};

type StateProps = {
  contentKey: LeftColumnContent;
  settingsScreen: SettingsScreens;
  isChatOpen: boolean;
  isGlassEnabled: boolean;
};

type Tab = 'chats' | 'contacts' | 'settings';

const TABS: { key: Tab; icon: IconName; labelKey: RegularLangKey }[] = [
  { key: 'chats', icon: 'comments', labelKey: 'FilterChats' },
  { key: 'contacts', icon: 'user', labelKey: 'Contacts' },
  { key: 'settings', icon: 'settings', labelKey: 'Settings' },
];

// Floating iOS 26-style tab bar for the mobile layout
const LiquidTabBar = ({
  isMobile,
  contentKey,
  settingsScreen,
  isChatOpen,
  isGlassEnabled,
}: OwnProps & StateProps) => {
  const { openLeftColumnContent, openSettingsScreen } = getActions();

  const lang = useLang();

  const activeTab = getActiveTab(contentKey, settingsScreen);

  const handleTabClick = useLastCallback((tab: Tab) => {
    if (tab === activeTab) return;

    if (tab === 'settings') {
      openSettingsScreen({ screen: SettingsScreens.Main });
    } else {
      openLeftColumnContent({
        contentKey: tab === 'contacts' ? LeftColumnContent.Contacts : LeftColumnContent.ChatList,
      });
    }
  });

  if (!isMobile || !isGlassEnabled || isChatOpen || !activeTab) return undefined;

  return (
    <nav className={styles.root} dir={lang.isRtl ? 'rtl' : undefined}>
      {TABS.map(({ key, icon, labelKey }) => (
        <button
          key={key}
          type="button"
          className={buildClassName(styles.tab, key === activeTab && styles.active)}
          onClick={() => handleTabClick(key)}
        >
          <Icon name={icon} className={styles.icon} />
          <span className={styles.label}>{lang(labelKey)}</span>
        </button>
      ))}
    </nav>
  );
};

function getActiveTab(contentKey: LeftColumnContent, settingsScreen: SettingsScreens): Tab | undefined {
  switch (contentKey) {
    case LeftColumnContent.ChatList:
      return 'chats';
    case LeftColumnContent.Contacts:
      return 'contacts';
    case LeftColumnContent.Settings:
      return settingsScreen === SettingsScreens.Main ? 'settings' : undefined;
    default:
      return undefined;
  }
}

export default memo(withGlobal<OwnProps>(
  (global): Complete<StateProps> => {
    const { leftColumn } = selectTabState(global);

    return {
      contentKey: leftColumn.contentKey,
      settingsScreen: leftColumn.settingsScreen,
      isChatOpen: Boolean(selectCurrentMessageList(global)),
      isGlassEnabled: selectLiquidSettings(global).isGlassEnabled,
    };
  },
)(LiquidTabBar));
