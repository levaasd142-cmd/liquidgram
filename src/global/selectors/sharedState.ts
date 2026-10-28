import type { GhostModeSettings, GlobalState, LiquidSettings } from '../types';

type GhostModeFeature = Exclude<keyof GhostModeSettings, 'isEnabled'>;

export const DEFAULT_LIQUID_SETTINGS: LiquidSettings = {
  isGlassEnabled: true,
  isRefractionEnabled: true,
  glassIntensity: 60,
  isAntiDeleteEnabled: true,
  isEditHistoryEnabled: true,
  isStreamerModeEnabled: false,
  shouldShowIds: true,
  shouldShowSeconds: false,
  shouldHideStories: false,
};

export const DEFAULT_GHOST_MODE_SETTINGS: GhostModeSettings = {
  isEnabled: false,
  shouldHideReadReceipts: true,
  shouldHideTyping: true,
  shouldStayOffline: true,
  shouldHideStoryViews: true,
  shouldHideMediaPlayback: true,
  shouldReadOnSend: true,
};

export function selectSharedState<T extends GlobalState>(
  global: T,
) {
  return global.sharedState;
}

export function selectSharedSettings<T extends GlobalState>(
  global: T,
) {
  return selectSharedState(global).settings;
}

export function selectMessageTextSize<T extends GlobalState>(global: T) {
  return selectSharedSettings(global).messageTextSize;
}

export function selectAnimationLevel<T extends GlobalState>(
  global: T,
) {
  return selectSharedSettings(global).animationLevel;
}

export function selectLiquidSettings<T extends GlobalState>(global: T) {
  return selectSharedSettings(global).liquid || DEFAULT_LIQUID_SETTINGS;
}

export function selectGhostModeSettings<T extends GlobalState>(global: T) {
  return selectSharedSettings(global).ghostMode || DEFAULT_GHOST_MODE_SETTINGS;
}

export function selectIsGhostFeatureActive<T extends GlobalState>(
  global: T, feature: GhostModeFeature,
) {
  const ghostMode = selectGhostModeSettings(global);
  return ghostMode.isEnabled && ghostMode[feature];
}
