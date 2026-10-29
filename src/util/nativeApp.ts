// Client for the iPhone app in `ios/`, whose `Resources/bridge.js` adds the functions of `window.__liquidgramNative`.
// Outside the app the object is missing, so every function does nothing.

export type NativeHapticStyle = 'selection' | 'light' | 'medium' | 'heavy' | 'soft' | 'rigid'
  | 'success' | 'warning' | 'error';

export type NativeAppAction = {
  type: 'openSavedMessages' | 'openSearch' | 'newMessage' | 'toggleGhostMode' | 'scrollToTop';
} | {
  type: 'openLink';
  url: string;
};

// Seconds in the background after which the app locks
export const APP_LOCK_DELAYS = [0, 60, 300, 900, 3600] as const;
const BIOMETRY_TYPES = ['faceID', 'touchID', 'opticID', 'passcode', 'none'] as const;
const SETTING_ERRORS = ['authFailed', 'cancelled', 'notAvailable', 'invalid'] as const;

export type NativeAppLockDelay = typeof APP_LOCK_DELAYS[number];
export type NativeBiometryType = typeof BIOMETRY_TYPES[number];
// `failed` stands for requests that the app did not answer or answered without a known error
export type NativeSettingError = typeof SETTING_ERRORS[number] | 'failed';

export type NativeSettings = {
  isAppLockEnabled: boolean;
  appLockDelay: NativeAppLockDelay;
  biometryType: NativeBiometryType;
  isPrivacyShieldEnabled: boolean;
  areHapticsEnabled: boolean;
  isInAppBrowserEnabled: boolean;
  // The name of the alternate icon, `undefined` for the primary one
  appIcon?: string;
  appIcons: string[];
  canChangeAppIcon: boolean;
};

// Values that `setNativeSetting` takes, by the keys of the app's settings
export type NativeSettingValues = {
  appLockEnabled: boolean;
  appLockDelay: NativeAppLockDelay;
  privacyShieldEnabled: boolean;
  hapticsEnabled: boolean;
  inAppBrowserEnabled: boolean;
};

export type NativeSettingsResult = {
  settings?: NativeSettings;
  error?: NativeSettingError;
};

// The settings as the app sends them
type NativeSettingsPayload = {
  appLockEnabled: boolean;
  appLockDelay: number;
  biometryType: string;
  privacyShieldEnabled: boolean;
  hapticsEnabled: boolean;
  inAppBrowserEnabled: boolean;
  appIcon: string | null;
  appIcons: string[];
  supportsAlternateIcons: boolean;
};

type NativeResponse = {
  ok?: boolean;
  error?: string;
  settings?: Partial<NativeSettingsPayload>;
};

const DEFAULT_APP_LOCK_DELAY: NativeAppLockDelay = 60;
// Actions that arrive while no screen handles them, such as under the passcode lock screen, wait for the next handler
const MAX_PENDING_ACTIONS = 10;

let actionHandler: ((action: NativeAppAction) => void) | undefined;
const pendingActions: NativeAppAction[] = [];
let lastSettings: NativeSettings | undefined;

// The settings from the last answer of the app, so a screen can show them before it asks again
export function getLastNativeSettings() {
  return lastSettings;
}

export async function requestNativeSettings() {
  const response = await requestNative('getNativeSettings');
  return saveSettings(response?.settings);
}

export function setNativeSetting<T extends keyof NativeSettingValues>(key: T, value: NativeSettingValues[T]) {
  return requestNativeChange('setNativeSetting', { key, value });
}

export function setNativeAppIcon(name?: string) {
  // The app takes `null` for the primary icon
  // eslint-disable-next-line no-null/no-null
  return requestNativeChange('setAppIcon', { name: name ?? null });
}

export function triggerHaptic(style: NativeHapticStyle) {
  window.__liquidgramNative?.haptic?.(style);
}

export function lockNativeApp() {
  window.__liquidgramNative?.postMessage?.({ type: 'lockNow' });
}

// Opens the page of the app in the iOS Settings, which holds its notification settings
export function openNativeSystemSettings() {
  window.__liquidgramNative?.postMessage?.({ type: 'openSystemSettings' });
}

// The app keeps its actions until the page registers a handler. Returns the function that unregisters it.
export function registerNativeActionHandler(handler: (action: NativeAppAction) => void) {
  const native = window.__liquidgramNative;
  if (!native?.setActionHandler) return undefined;

  actionHandler = handler;
  pendingActions.splice(0).forEach(handler);
  // Each call tells the app again that the page is ready for actions
  native.setActionHandler(dispatchNativeAction);

  return () => {
    if (actionHandler === handler) actionHandler = undefined;
  };
}

function dispatchNativeAction(action: NativeAppAction) {
  if (actionHandler) {
    actionHandler(action);
  } else if (pendingActions.length < MAX_PENDING_ACTIONS) {
    pendingActions.push(action);
  }
}

async function requestNativeChange(type: string, payload: AnyLiteral): Promise<NativeSettingsResult> {
  const response = await requestNative(type, payload);
  const settings = saveSettings(response?.settings);
  if (response?.ok) return { settings };

  const error = SETTING_ERRORS.find((knownError) => knownError === response?.error);
  return { settings, error: error || 'failed' };
}

async function requestNative(type: string, payload?: AnyLiteral): Promise<NativeResponse | undefined> {
  const native = window.__liquidgramNative;
  if (!native?.request) return undefined;

  try {
    return await native.request(type, payload);
  } catch {
    // The app did not answer in time
    return undefined;
  }
}

function saveSettings(payload?: Partial<NativeSettingsPayload>) {
  if (!payload) return undefined;

  lastSettings = buildNativeSettings(payload);
  return lastSettings;
}

function buildNativeSettings({
  appLockEnabled, appLockDelay, biometryType, privacyShieldEnabled, hapticsEnabled, inAppBrowserEnabled, appIcon,
  appIcons, supportsAlternateIcons,
}: Partial<NativeSettingsPayload>): NativeSettings {
  return {
    isAppLockEnabled: Boolean(appLockEnabled),
    appLockDelay: APP_LOCK_DELAYS.find((delay) => delay === appLockDelay) ?? DEFAULT_APP_LOCK_DELAY,
    biometryType: BIOMETRY_TYPES.find((type) => type === biometryType) || 'none',
    isPrivacyShieldEnabled: Boolean(privacyShieldEnabled),
    areHapticsEnabled: Boolean(hapticsEnabled),
    isInAppBrowserEnabled: Boolean(inAppBrowserEnabled),
    appIcon: appIcon || undefined,
    appIcons: Array.isArray(appIcons) ? appIcons : [],
    canChangeAppIcon: Boolean(supportsAlternateIcons),
  };
}
