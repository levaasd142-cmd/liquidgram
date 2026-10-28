import type { ApiLanguage } from '../../api/types';
import type {
  AnimationLevel, FoldersPosition, IThemeSettings, PerformanceType, Point, Size, ThemeKey, TimeFormat,
} from '../../types';

export interface SharedState {
  cacheVersion: number;
  settings: SharedSettings;
  isInitial?: true;
}

export interface SharedSettings {
  shouldUseSystemTheme: boolean;
  theme: ThemeKey;
  themes: Partial<Record<ThemeKey, IThemeSettings>>;
  language: string;
  languages?: ApiLanguage[];
  customLanguages?: ApiLanguage[];
  performance: PerformanceType;
  messageTextSize: number;
  instantViewFontSizeAdjust: number;
  animationLevel: AnimationLevel;
  foldersPosition: FoldersPosition;
  // This can be deleted after September 2025, along with the corresponding migration
  wasAnimationLevelSetManually?: boolean;
  messageSendKeyCombo: 'enter' | 'ctrl-enter';
  shouldReplaceTextShortcuts: boolean;
  browserCachedPosition?: Point;
  browserCachedSize?: Size;
  timeFormat: TimeFormat;
  wasTimeFormatSetManually: boolean;
  isConnectionStatusMinimized: boolean;
  canDisplayChatInTitle: boolean;
  shouldForceHttpTransport?: boolean;
  shouldAllowHttpTransport?: boolean;
  shouldCollectDebugLogs?: boolean;
  shouldDebugExportedSenders?: boolean;
  shouldWarnAboutFiles?: boolean;
  shouldSkipBrowserCloseConfirmation: boolean;
  shouldKeepLockScreenBackground: boolean;
  liquid?: LiquidSettings;
  ghostMode?: GhostModeSettings;
}

export interface LiquidSettings {
  isGlassEnabled: boolean;
  isRefractionEnabled: boolean;
  glassIntensity: number;
  isAntiDeleteEnabled: boolean;
  isEditHistoryEnabled: boolean;
  isStreamerModeEnabled: boolean;
  shouldShowIds: boolean;
  shouldShowSeconds: boolean;
  shouldHideStories: boolean;
}

export interface GhostModeSettings {
  isEnabled: boolean;
  shouldHideReadReceipts: boolean;
  shouldHideTyping: boolean;
  shouldStayOffline: boolean;
  shouldHideStoryViews: boolean;
  shouldHideMediaPlayback: boolean;
  shouldReadOnSend: boolean;
}
