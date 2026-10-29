import { useEffect } from '@teact';

import { IS_IOS_APP } from '../../util/browser/windowEnvironment';
import { createSignal } from '../../util/signals';
import useLastCallback from '../useLastCallback';

// A `WKWebView` gets the focus only with the first tap, so the iOS app is in the background while it is hidden
const [getIsInBackgroundLocal, setIsInBackground] = createSignal(
  IS_IOS_APP ? document.visibilityState === 'hidden' : !document.hasFocus(),
);
export const getIsInBackground = getIsInBackgroundLocal;

function handleBlur() {
  setIsInBackground(true);
}

function handleFocus() {
  setIsInBackground(false);
}

function handleVisibilityChange() {
  setIsInBackground(document.visibilityState === 'hidden');
}

if (IS_IOS_APP) {
  document.addEventListener('visibilitychange', handleVisibilityChange);
} else {
  window.addEventListener('blur', handleBlur);
  window.addEventListener('focus', handleFocus);
}

export default function useBackgroundMode(
  onBlur?: AnyToVoidFunction,
  onFocus?: AnyToVoidFunction,
  isDisabled = false,
) {
  const lastOnBlur = useLastCallback(onBlur);
  const lastOnFocus = useLastCallback(onFocus);

  useEffect(() => {
    if (isDisabled) {
      return undefined;
    }

    if (getIsInBackground()) {
      lastOnBlur();
    }

    return getIsInBackground.subscribe(() => {
      if (getIsInBackground()) {
        lastOnBlur();
      } else {
        lastOnFocus();
      }
    });
  }, [isDisabled, lastOnBlur, lastOnFocus]);
}

export function isBackgroundModeActive() {
  return getIsInBackground();
}
