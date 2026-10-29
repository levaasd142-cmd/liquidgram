import { useEffect } from '../lib/teact/teact';

import { IS_IOS_APP } from '../util/browser/windowEnvironment';
import { addThemeColorOverlay } from '../util/themeColor';

const DEFAULT_OVERLAY_COLOR = '#000000';

// The iOS app paints the strip under the status bar with the page's `theme-color`, so a full-screen overlay sets it to
// the color at the top of the overlay while it is open
export default function useOverlayThemeColor(isActive: boolean, color = DEFAULT_OVERLAY_COLOR) {
  useEffect(() => {
    if (!IS_IOS_APP || !isActive) return undefined;

    return addThemeColorOverlay(color);
  }, [isActive, color]);
}
