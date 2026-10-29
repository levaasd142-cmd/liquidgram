import { useEffect } from '../lib/teact/teact';
import { getActions, getGlobal } from '../global';

import type { NativeAppAction } from '../util/nativeApp';
import { LeftColumnContent } from '../types';

import { RE_TG_LINK, RE_TME_LINK } from '../config';
import { requestMeasure, requestMutation } from '../lib/fasterdom/fasterdom';
import {
  selectCurrentMessageList,
  selectIsMediaViewerOpen,
  selectIsRightColumnShown,
  selectIsStoryViewerOpen,
  selectTabState,
} from '../global/selectors';
import { selectGhostModeSettings } from '../global/selectors/sharedState';
import { registerNativeActionHandler } from '../util/nativeApp';
import useLastCallback from './useLastCallback';

const LEFT_COLUMN_SCROLLABLE_SELECTOR = '#LeftColumn .custom-scroll';
const RIGHT_COLUMN_SCROLLABLE_SELECTOR = '#RightColumn .custom-scroll';
const MESSAGE_LIST_SELECTOR = '.messages-layout .Transition_slide-active > .MessageList';
const RE_SETTINGS_LINK = /^tg:(\/\/)?settings\b/i;

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
        // Settings open in the left column, which an open chat can hide
        if (RE_SETTINGS_LINK.test(action.url)) revealLeftColumn();
        openTelegramLink({ url: action.url });
        break;
      case 'scrollToTop':
        scrollVisibleListToTop();
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
    closeViewers();
    revealLeftColumn();
    openLeftColumnContent({ contentKey });
  }

  // The mobile layout shows the left column only without an open chat, and the tablet layout can hide it
  function revealLeftColumn() {
    const global = getGlobal();
    if (isMobile && selectCurrentMessageList(global)) {
      openChat({ id: undefined, shouldReplaceHistory: true });
    } else if (!selectTabState(global).isLeftColumnShown) {
      toggleLeftColumn();
    }
  }

  // Scrolls the list on screen to the top, as a tap on the status bar does in iOS: on a phone, the profile or the
  // messages of an open chat, otherwise the lists of the left column, such as the chat list
  function scrollVisibleListToTop() {
    const global = getGlobal();
    const selector = !isMobile || !selectCurrentMessageList(global) ? LEFT_COLUMN_SCROLLABLE_SELECTOR
      : selectIsRightColumnShown(global, isMobile) ? RIGHT_COLUMN_SCROLLABLE_SELECTOR : MESSAGE_LIST_SELECTOR;

    requestMeasure(() => {
      const scrolledElements = Array.from(document.querySelectorAll<HTMLElement>(selector))
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
