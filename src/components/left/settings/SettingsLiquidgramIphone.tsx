import { memo, useEffect, useMemo, useState } from '../../../lib/teact/teact';
import { getActions } from '../../../global';

import type { RegularLangKey } from '../../../types/language';
import type { LangFn } from '../../../util/localization';
import type {
  NativeAppLockDelay,
  NativeBiometryType,
  NativeSettingError,
  NativeSettingsResult,
  NativeSettingValues,
} from '../../../util/nativeApp';
import type { IRadioOption } from '../../ui/RadioGroup';

import buildClassName from '../../../util/buildClassName';
import { omit } from '../../../util/iteratees';
import {
  APP_LOCK_DELAYS,
  getLastNativeSettings,
  lockNativeApp,
  openNativeSystemSettings,
  requestNativeSettings,
  setNativeAppIcon,
  setNativeSetting,
} from '../../../util/nativeApp';

import useLang from '../../../hooks/useLang';
import useLastCallback from '../../../hooks/useLastCallback';

import Island, { IslandDescription, IslandTitle } from '../../gili/layout/Island';
import Checkbox from '../../ui/Checkbox';
import ListItem from '../../ui/ListItem';
import RadioGroup from '../../ui/RadioGroup';

import styles from './SettingsLiquidgram.module.scss';

const APP_LOCK_LANG_KEYS: Record<NativeBiometryType, RegularLangKey> = {
  faceID: 'LiquidAppLockFaceId',
  touchID: 'LiquidAppLockTouchId',
  opticID: 'LiquidAppLockOpticId',
  passcode: 'LiquidAppLockPasscode',
  none: 'LiquidAppLock',
};

const ERROR_LANG_KEYS: Record<NativeSettingError, RegularLangKey> = {
  authFailed: 'LiquidAuthFailed',
  cancelled: 'LiquidAuthCancelled',
  notAvailable: 'LiquidAppLockUnavailable',
  invalid: 'SomethingWentWrong',
  failed: 'SomethingWentWrong',
};

// The primary icon, whose preview is named after its icon set like the previews of the alternate ones
const PRIMARY_APP_ICON = 'AppIcon';
const APP_ICON_PREVIEWS_PATH = './ios-app-icons';
const APP_ICON_PREFIX = 'AppIcon';
const APP_ICON_LANG_KEYS: Partial<Record<string, RegularLangKey>> = {
  [PRIMARY_APP_ICON]: 'LiquidAppIconDefault',
  AppIconMidnight: 'LiquidAppIconMidnight',
  AppIconAurora: 'LiquidAppIconAurora',
  AppIconGlass: 'LiquidAppIconGlass',
  AppIconClassic: 'LiquidAppIconClassic',
};

const SECONDS_IN_MINUTE = 60;
const SECONDS_IN_HOUR = 60 * SECONDS_IN_MINUTE;

// Settings of the iPhone app, which keeps them itself, see `util/nativeApp.ts`
const SettingsLiquidgramIphone = () => {
  const { showNotification } = getActions();

  const lang = useLang();

  const [settings, setSettings] = useState(getLastNativeSettings);
  // Values of the requests that the app has not answered yet
  const [pendingValues, setPendingValues] = useState<Partial<NativeSettingValues>>({});
  const [pendingAppIcon, setPendingAppIcon] = useState<string>();

  const updateSettings = useLastCallback(async () => {
    const newSettings = await requestNativeSettings();
    if (newSettings) setSettings(newSettings);
  });

  useEffect(() => {
    // The user can turn off the passcode or set up Face ID in the iOS Settings while the app is in the background
    function handleVisibilityChange() {
      if (document.visibilityState === 'visible') void updateSettings();
    }

    void updateSettings();
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [updateSettings]);

  const appLockDelayOptions = useMemo((): IRadioOption[] => APP_LOCK_DELAYS.map((delay) => ({
    value: String(delay),
    label: formatAppLockDelay(lang, delay),
  })), [lang]);

  const appIcons = useMemo(() => (settings ? [PRIMARY_APP_ICON, ...settings.appIcons] : []), [settings]);

  const applyResult = useLastCallback((result: NativeSettingsResult, errorLangKey?: RegularLangKey) => {
    if (result.settings) setSettings(result.settings);
    // Without an answer the state in the app is unknown, so the screen asks for it again
    if (result.error === 'failed') void updateSettings();
    if (result.error) showNotification({ message: { key: errorLangKey || ERROR_LANG_KEYS[result.error] } });
  });

  const changeSetting = useLastCallback(async <T extends keyof NativeSettingValues>(
    key: T, value: NativeSettingValues[T],
  ) => {
    setPendingValues((current) => ({ ...current, [key]: value }));
    const result = await setNativeSetting(key, value);
    setPendingValues((current) => omit(current, [key]));
    applyResult(result);
  });

  const handleAppLockChange = useLastCallback((isChecked: boolean) => {
    void changeSetting('appLockEnabled', isChecked);
  });

  const handleAppLockDelayChange = useLastCallback((value: string) => {
    const delay = APP_LOCK_DELAYS.find((option) => String(option) === value);
    if (delay !== undefined) void changeSetting('appLockDelay', delay);
  });

  const handlePrivacyShieldChange = useLastCallback((isChecked: boolean) => {
    void changeSetting('privacyShieldEnabled', isChecked);
  });

  const handleHapticsChange = useLastCallback((isChecked: boolean) => {
    void changeSetting('hapticsEnabled', isChecked);
  });

  const handleInAppBrowserChange = useLastCallback((isChecked: boolean) => {
    void changeSetting('inAppBrowserEnabled', isChecked);
  });

  const handleAppIconClick = useLastCallback(async (e: React.MouseEvent<HTMLButtonElement>) => {
    const { name } = e.currentTarget.dataset;
    if (!name || pendingAppIcon || name === (settings?.appIcon || PRIMARY_APP_ICON)) return;

    setPendingAppIcon(name);
    const result = await setNativeAppIcon(name === PRIMARY_APP_ICON ? undefined : name);
    setPendingAppIcon(undefined);
    applyResult(result, 'LiquidAppIconFailed');
  });

  if (!settings) return undefined;

  const { isAppLockEnabled, biometryType } = settings;
  const isAppLockAvailable = biometryType !== 'none';
  const isAppLockPending = pendingValues.appLockEnabled !== undefined;
  const selectedAppIcon = pendingAppIcon || settings.appIcon || PRIMARY_APP_ICON;

  return (
    <>
      <IslandTitle dir={lang.isRtl ? 'rtl' : undefined}>{lang('LiquidSectionIphone')}</IslandTitle>
      <Island>
        {/* The label depends on the biometry, so search finds the row by its anchor */}
        <div data-settings-anchor="LiquidAppLock">
          <Checkbox
            label={lang(APP_LOCK_LANG_KEYS[biometryType])}
            subLabel={lang(isAppLockAvailable ? 'LiquidAppLockInfo' : 'LiquidAppLockUnavailable')}
            checked={pendingValues.appLockEnabled ?? isAppLockEnabled}
            disabled={!isAppLockAvailable || isAppLockPending}
            isLoading={isAppLockPending}
            teactExperimentControlled
            onCheck={handleAppLockChange}
          />
        </div>
        {isAppLockEnabled && (
          <ListItem icon="lock" narrow onClick={lockNativeApp}>
            {lang('LiquidAppLockNow')}
          </ListItem>
        )}
      </Island>

      {isAppLockEnabled && (
        <>
          <IslandTitle dir={lang.isRtl ? 'rtl' : undefined}>{lang('PasscodeAutoLockTitle')}</IslandTitle>
          <Island>
            <RadioGroup
              name="liquid-app-lock-delay"
              options={appLockDelayOptions}
              selected={String(pendingValues.appLockDelay ?? settings.appLockDelay)}
              onChange={handleAppLockDelayChange}
            />
          </Island>
          <IslandDescription>{lang('LiquidAppLockDelayInfo')}</IslandDescription>
        </>
      )}

      <Island>
        {/* The app hides its content in the app switcher whenever the lock is on */}
        <Checkbox
          label={lang('LiquidPrivacyShield')}
          subLabel={lang(isAppLockEnabled ? 'LiquidPrivacyShieldWithLock' : 'LiquidPrivacyShieldInfo')}
          checked={isAppLockEnabled || (pendingValues.privacyShieldEnabled ?? settings.isPrivacyShieldEnabled)}
          disabled={isAppLockEnabled}
          teactExperimentControlled
          onCheck={handlePrivacyShieldChange}
        />
        <Checkbox
          label={lang('LiquidHaptics')}
          subLabel={lang('LiquidHapticsInfo')}
          checked={pendingValues.hapticsEnabled ?? settings.areHapticsEnabled}
          teactExperimentControlled
          onCheck={handleHapticsChange}
        />
        <Checkbox
          label={lang('LiquidInAppBrowser')}
          subLabel={lang('LiquidInAppBrowserInfo')}
          checked={pendingValues.inAppBrowserEnabled ?? settings.isInAppBrowserEnabled}
          teactExperimentControlled
          onCheck={handleInAppBrowserChange}
        />
        <ListItem icon="unmute" narrow onClick={openNativeSystemSettings}>
          {lang('LiquidIosNotifications')}
        </ListItem>
      </Island>

      {settings.canChangeAppIcon && (
        <>
          <IslandTitle dir={lang.isRtl ? 'rtl' : undefined}>{lang('LiquidAppIcon')}</IslandTitle>
          <Island>
            <div className={styles.appIcons}>
              {appIcons.map((name) => {
                const isSelected = name === selectedAppIcon;

                return (
                  <button
                    key={name}
                    type="button"
                    className={buildClassName(styles.appIcon, isSelected && styles.appIconSelected)}
                    data-name={name}
                    aria-pressed={isSelected}
                    onClick={handleAppIconClick}
                  >
                    <img
                      className={styles.appIconPreview}
                      src={`${APP_ICON_PREVIEWS_PATH}/${name}.png`}
                      alt=""
                      draggable={false}
                    />
                    <span className={styles.appIconName}>{formatAppIconName(lang, name)}</span>
                  </button>
                );
              })}
            </div>
          </Island>
        </>
      )}
    </>
  );
};

function formatAppLockDelay(lang: LangFn, delay: NativeAppLockDelay) {
  if (!delay) return lang('LiquidAppLockImmediately');

  if (delay < SECONDS_IN_HOUR) {
    const minutes = delay / SECONDS_IN_MINUTE;
    return lang('Minutes', { count: minutes }, { pluralValue: minutes });
  }

  const hours = delay / SECONDS_IN_HOUR;
  return lang('Hours', { count: hours }, { pluralValue: hours });
}

// Icons that a newer app adds before the page knows them show their name without the prefix
function formatAppIconName(lang: LangFn, name: string) {
  const langKey = APP_ICON_LANG_KEYS[name];
  return langKey ? lang(langKey) : name.replace(APP_ICON_PREFIX, '');
}

export default memo(SettingsLiquidgramIphone);
