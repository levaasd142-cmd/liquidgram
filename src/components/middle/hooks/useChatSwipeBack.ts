import type { ElementRef } from '../../../lib/teact/teact';
import { useEffect, useRef } from '../../../lib/teact/teact';
import { getActions, getGlobal } from '../../../global';

import type { MessageList } from '../../../types';

import { EDITABLE_INPUT_CSS_SELECTOR } from '../../../config';
import { requestMutation } from '../../../lib/fasterdom/fasterdom';
import { selectCurrentMessageList } from '../../../global/selectors';
import { IS_IOS_APP, IS_TOUCH_ENV } from '../../../util/browser/windowEnvironment';
import { captureSwipeBack, settleSwipeLayers } from '../../../util/swipeBack';
import {
  dragControlledSwipe, releaseControlledSwipe, startControlledSwipe,
} from '../../../util/swipeController';

import useLastCallback from '../../../hooks/useLastCallback';
import { useStateRef } from '../../../hooks/useStateRef';

type SwipeMode = 'chat' | 'messageList' | 'messageListOnRelease';

// The footer has the composer with its record button, the bot keyboard and the action bars
const EXCLUDED_SELECTOR = '.middle-column-footer';
// The chat casts it on the chat list while they move side by side
const EDGE_SHADOW = '0 0 1.5rem rgba(0, 0, 0, 0.15)';
// The layout gives the chat list its place within a few frames after the chat closes
const LAYOUT_TIMEOUT = 1000;

// The iPhone app's swipe back from a chat: the chat follows the finger, and the chat list comes in next to it, as when
// the chat closes with the Back button. The chat column is transparent over the shared wallpaper, so the list slides
// beside the chat rather than under it. From a stacked message list, such as the pinned messages, the transition of
// the message lists follows the finger, sliding them side by side; without animations the list closes on release.
// RTL mirrors the direction.
//
// Returns a ref that is set while the message lists slide for a swipe. The transition then uses the sliding animation,
// played forward in RTL, where the swipe goes to the left.
export default function useChatSwipeBack({
  middleColumnRef,
  isEnabled,
  isRtl,
  hasPreviousMessageList,
  canAnimateMessageLists,
  onBack,
}: {
  middleColumnRef: ElementRef<HTMLDivElement>;
  isEnabled: boolean;
  isRtl?: boolean;
  hasPreviousMessageList: boolean;
  canAnimateMessageLists: boolean;
  onBack: NoneToVoidFunction;
}) {
  const { disableHistoryAnimations, openPreviousChat, processOpenChatOrThread } = getActions();

  const isEnabledRef = useStateRef(isEnabled);
  const hasPreviousMessageListRef = useStateRef(hasPreviousMessageList);
  const canAnimateMessageListsRef = useStateRef(canAnimateMessageLists);
  const shouldSlideMessageListsRef = useRef(false);
  const handleBack = useLastCallback(onBack);

  useEffect(() => {
    if (!IS_IOS_APP || !IS_TOUCH_ENV) return undefined;

    const middleColumn = middleColumnRef.current;
    const leftColumn = document.getElementById('LeftColumn');
    const main = document.getElementById('Main');
    if (!middleColumn || !leftColumn || !main) return undefined;

    const columns = [middleColumn, leftColumn];
    const direction = isRtl ? -1 : 1;
    let mode: SwipeMode | undefined;
    let areColumnsMoving = false;
    let width = 0;
    let offset = 0;
    let isMoveScheduled = false;
    // The message list to reopen when a swipe back from it is cancelled
    let messageListToRestore: MessageList | undefined;

    function moveColumns(columnOffset: number) {
      middleColumn!.style.transform = `translate3d(${direction * columnOffset}px, 0, 0)`;
      leftColumn!.style.transform = `translate3d(${direction * (columnOffset - width)}px, 0, 0)`;
    }

    function resetColumns() {
      areColumnsMoving = false;
      requestMutation(() => {
        columns.forEach((column) => {
          column.style.transition = '';
          column.style.transform = '';
        });
        middleColumn!.style.boxShadow = '';
        leftColumn!.style.removeProperty('--layer-blackout-opacity');
      });
    }

    function blurMessageInput() {
      document.querySelector<HTMLElement>(EDITABLE_INPUT_CSS_SELECTOR)?.blur();
    }

    // Takes off the inline positions once the layout puts the columns at the same place
    function resetColumnsAfterChatCloses(startedAt = Date.now()) {
      if (main!.classList.contains('left-column-open') || Date.now() - startedAt > LAYOUT_TIMEOUT) {
        resetColumns();
        return;
      }

      requestAnimationFrame(() => resetColumnsAfterChatCloses(startedAt));
    }

    function restoreMessageList() {
      if (!messageListToRestore) return;

      const { chatId, threadId, type } = messageListToRestore;
      messageListToRestore = undefined;
      processOpenChatOrThread({ chatId, threadId, type });
    }

    function startChatSwipe() {
      mode = 'chat';
      areColumnsMoving = true;
      width = middleColumn!.offsetWidth;
      offset = 0;
      requestMutation(() => {
        columns.forEach((column) => {
          column.style.transition = 'none';
        });
        middleColumn!.style.boxShadow = EDGE_SHADOW;
        // The chat list loses its shade as it comes in, as it does when the chat closes
        leftColumn!.style.setProperty('--layer-blackout-opacity', '0');
      });
    }

    function endChatSwipe(shouldGoBack: boolean, velocity: number) {
      const targetOffset = shouldGoBack ? width : 0;
      settleSwipeLayers(columns, targetOffset - offset, velocity, () => moveColumns(targetOffset), () => {
        if (!shouldGoBack) {
          resetColumns();
          return;
        }

        // The columns are already where the layout puts them, so the layout changes without its animation
        disableHistoryAnimations();
        handleBack();
        resetColumnsAfterChatCloses();
      });
    }

    const releaseSwipe = captureSwipeBack(middleColumn, {
      isRtl,
      excludedClosestSelector: EXCLUDED_SELECTOR,
      // Message bubbles swipe to reply in the direction that goes back in RTL
      edgeOnlyClosestSelector: isRtl ? '.Message' : undefined,
      selectorToPreventScroll: '.MessageList',
      getIsEnabled: () => isEnabledRef.current && !areColumnsMoving,

      onStart() {
        if (!hasPreviousMessageListRef.current) {
          startChatSwipe();
          return;
        }

        if (!canAnimateMessageListsRef.current) {
          mode = 'messageListOnRelease';
          return;
        }

        mode = 'messageList';
        messageListToRestore = selectCurrentMessageList(getGlobal());
        shouldSlideMessageListsRef.current = true;
        // The transition to the previous message list follows the finger from here on
        startControlledSwipe({ dragOffsetX: 0, dragOffsetY: 0 });
        openPreviousChat();
      },

      onMove(newOffset) {
        if (mode === 'messageList') {
          dragControlledSwipe({ dragOffsetX: direction * newOffset, dragOffsetY: 0 });
          return;
        }

        if (mode !== 'chat') return;

        offset = Math.min(newOffset, width);
        if (isMoveScheduled) return;

        isMoveScheduled = true;
        requestMutation(() => {
          isMoveScheduled = false;
          if (mode === 'chat') moveColumns(offset);
        });
      },

      onEnd(shouldGoBack, velocity) {
        const endedMode = mode;
        mode = undefined;
        if (shouldGoBack) blurMessageInput();

        switch (endedMode) {
          case 'chat':
            endChatSwipe(shouldGoBack, velocity);
            break;
          case 'messageList':
            releaseControlledSwipe(restoreMessageList, shouldGoBack);
            shouldSlideMessageListsRef.current = false;
            if (shouldGoBack) messageListToRestore = undefined;
            break;
          case 'messageListOnRelease':
            if (shouldGoBack) openPreviousChat();
            break;
        }
      },
    });

    return () => {
      releaseSwipe();
      if (areColumnsMoving) resetColumns();
    };
  }, [canAnimateMessageListsRef, hasPreviousMessageListRef, isEnabledRef, isRtl, middleColumnRef]);

  return shouldSlideMessageListsRef;
}
