import { memo } from '../../../lib/teact/teact';
import { getActions, withGlobal } from '../../../global';

import type { GhostModeSettings, LiquidSettings } from '../../../global/types';
import type { RegularLangKey } from '../../../types/language';

import { selectGhostModeSettings, selectLiquidSettings } from '../../../global/selectors/sharedState';
import { IS_IOS_APP } from '../../../util/browser/windowEnvironment';
import { IS_GLASS_REFRACTION_SUPPORTED } from '../../../util/liquidGlass';

import useHistoryBack from '../../../hooks/useHistoryBack';
import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Island, { IslandDescription, IslandTitle } from '../../gili/layout/Island';
import Checkbox from '../../ui/Checkbox';
import ListItem from '../../ui/ListItem';
import RangeSlider from '../../ui/RangeSlider';
import SettingsLiquidgramIphone from './SettingsLiquidgramIphone';

import styles from './SettingsLiquidgram.module.scss';

type OwnProps = {
  isActive?: boolean;
  onReset: () => void;
};

type StateProps = {
  liquid: LiquidSettings;
  ghostMode: GhostModeSettings;
};

type GhostFeature = Exclude<keyof GhostModeSettings, 'isEnabled'>;

const GHOST_FEATURES: { key: GhostFeature; labelKey: RegularLangKey }[] = [
  { key: 'shouldHideReadReceipts', labelKey: 'LiquidGhostReadReceipts' },
  { key: 'shouldHideTyping', labelKey: 'LiquidGhostTyping' },
  { key: 'shouldStayOffline', labelKey: 'LiquidGhostOffline' },
  { key: 'shouldHideStoryViews', labelKey: 'LiquidGhostStories' },
  { key: 'shouldHideMediaPlayback', labelKey: 'LiquidGhostMedia' },
  { key: 'shouldReadOnSend', labelKey: 'LiquidGhostReadOnSend' },
];

const SettingsLiquidgram = ({
  isActive,
  liquid,
  ghostMode,
  onReset,
}: OwnProps & StateProps) => {
  const { setLiquidSettingOption, setGhostModeOption, markAllChatsRead } = getActions();

  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onReset,
  });

  const handleIntensityChange = useLastCallback((glassIntensity: number) => {
    setLiquidSettingOption({ glassIntensity });
  });

  const handleMarkAllRead = useLastCallback(() => {
    markAllChatsRead();
  });

  return (
    <div className="settings-content custom-scroll">
      <div className={styles.hero}>
        <div className={styles.heroGlass}>
          <div className={styles.heroLogo} />
        </div>
        <h3 className={styles.heroTitle}>Liquidgram</h3>
        <p className={styles.heroDescription} dir="auto">{lang('LiquidSettingsAbout')}</p>
      </div>

      {IS_IOS_APP && <SettingsLiquidgramIphone />}

      <IslandTitle dir={lang.isRtl ? 'rtl' : undefined}>{lang('LiquidSectionDesign')}</IslandTitle>
      <Island>
        <Checkbox
          label={lang('LiquidGlass')}
          subLabel={lang('LiquidGlassInfo')}
          checked={liquid.isGlassEnabled}
          onCheck={(isGlassEnabled) => setLiquidSettingOption({ isGlassEnabled })}
        />
        <Checkbox
          label={lang('LiquidRefraction')}
          subLabel={lang('LiquidRefractionInfo')}
          checked={liquid.isRefractionEnabled && IS_GLASS_REFRACTION_SUPPORTED}
          disabled={!liquid.isGlassEnabled || !IS_GLASS_REFRACTION_SUPPORTED}
          onCheck={(isRefractionEnabled) => setLiquidSettingOption({ isRefractionEnabled })}
        />
        <RangeSlider
          label={lang('LiquidGlassIntensity')}
          min={0}
          max={100}
          value={liquid.glassIntensity}
          disabled={!liquid.isGlassEnabled}
          renderValue={(value) => `${value}%`}
          onChange={handleIntensityChange}
        />
      </Island>

      <IslandTitle dir={lang.isRtl ? 'rtl' : undefined}>{lang('LiquidSectionGhost')}</IslandTitle>
      <Island>
        <Checkbox
          label={lang('LiquidGhostMode')}
          subLabel={lang('LiquidGhostModeInfo')}
          checked={ghostMode.isEnabled}
          onCheck={(isEnabled) => setGhostModeOption({ isEnabled })}
        />
        {GHOST_FEATURES.map(({ key, labelKey }) => (
          <Checkbox
            key={key}
            label={lang(labelKey)}
            checked={ghostMode[key]}
            disabled={!ghostMode.isEnabled}
            onCheck={(isChecked) => setGhostModeOption({ [key]: isChecked })}
          />
        ))}
      </Island>
      <IslandDescription>{lang('LiquidGhostDescription')}</IslandDescription>

      <IslandTitle dir={lang.isRtl ? 'rtl' : undefined}>{lang('LiquidSectionMessages')}</IslandTitle>
      <Island>
        <Checkbox
          label={lang('LiquidAntiDelete')}
          subLabel={lang('LiquidAntiDeleteInfo')}
          checked={liquid.isAntiDeleteEnabled}
          onCheck={(isAntiDeleteEnabled) => setLiquidSettingOption({ isAntiDeleteEnabled })}
        />
        <Checkbox
          label={lang('LiquidEditHistory')}
          subLabel={lang('LiquidEditHistoryInfo')}
          checked={liquid.isEditHistoryEnabled}
          onCheck={(isEditHistoryEnabled) => setLiquidSettingOption({ isEditHistoryEnabled })}
        />
        <Checkbox
          label={lang('LiquidShowSeconds')}
          checked={liquid.shouldShowSeconds}
          onCheck={(shouldShowSeconds) => setLiquidSettingOption({ shouldShowSeconds })}
        />
      </Island>

      <IslandTitle dir={lang.isRtl ? 'rtl' : undefined}>{lang('LiquidSectionInterface')}</IslandTitle>
      <Island>
        <Checkbox
          label={lang('LiquidStreamerMode')}
          subLabel={lang('LiquidStreamerModeInfo')}
          checked={liquid.isStreamerModeEnabled}
          onCheck={(isStreamerModeEnabled) => setLiquidSettingOption({ isStreamerModeEnabled })}
        />
        <Checkbox
          label={lang('LiquidShowIds')}
          subLabel={lang('LiquidShowIdsInfo')}
          checked={liquid.shouldShowIds}
          onCheck={(shouldShowIds) => setLiquidSettingOption({ shouldShowIds })}
        />
        <Checkbox
          label={lang('LiquidHideStories')}
          checked={liquid.shouldHideStories}
          onCheck={(shouldHideStories) => setLiquidSettingOption({ shouldHideStories })}
        />
        <ListItem icon="readchats" narrow onClick={handleMarkAllRead}>
          {lang('LiquidMarkAllRead')}
        </ListItem>
      </Island>
    </div>
  );
};

export default memo(withGlobal<OwnProps>(
  (global): Complete<StateProps> => {
    return {
      liquid: selectLiquidSettings(global),
      ghostMode: selectGhostModeSettings(global),
    };
  },
)(SettingsLiquidgram));
