import { useEffect } from '../lib/teact/teact';
import { getActions, getGlobal } from '../global';

import type { NativeAppAction } from '../util/nativeApp';
import { LeftColumnContent } from '../types';

import { RE_TG_LINK, RE_TME_LINK } from '../config';
import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import {
  selectCurrentMessageList,
  selectIsMediaViewerOpen,
  selectIsStoryViewerOpen,
  selectTabState,
} from '../global/selectors';
import { selectGhostModeSettings } from '../global/selectors/sharedState';
import { registerNativeActionHandler } from '../util/nativeApp';
import useLastCallback from './useLastCallback';

const LEFT_COLUMN_SCROLLABLE_SELECTOR = '#LeftColumn .custom-scroll';

// Performs the actions of the iPhone app: home-screen quick actions, Siri shortcuts, links that open the app and
// taps on the status bar
export default function useNativeAppActions(isMobile?: boolean) {
  const {
    openChat,
    openLeftColumnContent,
    setGhostModeOption,
    showNotification,
    openTelegramLink,
    closeMediaViewer,
    closeStoryViewer,
    toggleLeftColumn,
  } = getActions();

  const handleAction = useLastCallback((action: NativeAppAction) => {
    switch (action.type) {
      case 'openSavedMessages':
        closeViewers();
        openChat({ id: getGlobal().currentUserId, shouldReplaceHistory: true });
        break;
      case 'openSearch':
        openLeftColumnScreen(LeftColumnContent.GlobalSearch);
        break;
      case 'newMessage':
        openLeftColumnScreen(LeftColumnContent.Contacts);
        break;
      case 'toggleGhostMode': {
        const isEnabled = !selectGhostModeSettings(getGlobal()).isEnabled;
        setGhostModeOption({ isEnabled });
        showNotification({
          message: { key: isEnabled ? 'LiquidGhostEnabled' : 'LiquidGhostDisabled' },
          icon: isEnabled ? 'eye-crossed' : 'eye',
        });
        break;
      }
      case 'openLink':
        if (!isTelegramLink(action.url)) break;

        closeViewers();
        openTelegramLink({ url: action.url });
        break;
      case 'scrollToTop':
        scrollLeftColumnToTop();
        break;
    }
  });

  useEffect(() => registerNativeActionHandler(handleAction), [handleAction]);

  // Media and stories cover the screen, so they would hide the result of an action
  function closeViewers() {
    const global = getGlobal();
    if (selectIsMediaViewerOpen(global)) closeMediaViewer();
    if (selectIsStoryViewerOpen(global)) closeStoryViewer();
  }

  function openLeftColumnScreen(contentKey: LeftColumnContent) {
    const global = getGlobal();
    closeViewers();
    // The mobile layout shows the left column only without an open chat, and the tablet layout can hide it
    if (isMobile && selectCurrentMessageList(global)) {
      openChat({ id: undefined, shouldReplaceHistory: true });
    } else if (!selectTabState(global).isLeftColumnShown) {
      toggleLeftColumn();
    }

    openLeftColumnContent({ contentKey });
  }

  // Scrolls the lists of the left column, such as the chat list, to the top, as a tap on the status bar does in iOS
  function scrollLeftColumnToTop() {
    if (isMobile && selectCurrentMessageList(getGlobal())) return;

    requestMeasure(() => {
      const scrolledElements = Array.from(document.querySelectorAll<HTMLElement>(LEFT_COLUMN_SCROLLABLE_SELECTOR))
        .filter((element) => element.scrollTop > 0 && element.getClientRects().length > 0);

      requestMutation(() => {
        scrolledElements.forEach((element) => {
          element.scrollTo({ top: 0, behavior: 'smooth' });
        });
      });
    });
  }
}

// The app passes links from other apps, which `openTelegramLink` only expects to be Telegram ones
function isTelegramLink(url: unknown): url is string {
  return typeof url === 'string' && (RE_TG_LINK.test(url) || RE_TME_LINK.test(url));
}
