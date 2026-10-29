import type { ElementRef } from '../../../../lib/teact/teact';
import { useEffect, useRef } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import type { Signal } from '../../../../util/signals';

import { requestMeasure, requestMutation } from '../../../../lib/fasterdom/fasterdom';
import { IS_ANDROID, IS_TOUCH_ENV } from '../../../../util/browser/windowEnvironment';
import { captureEvents, getTouchOwner, SwipeDirection } from '../../../../util/captureEvents';
import { triggerHaptic } from '../../../../util/nativeApp';
import stopEvent from '../../../../util/stopEvent';
import windowSize from '../../../../util/windowSize';
import { REM } from '../../../common/helpers/mediaDimensions';
import { preventMessageInputBlur } from '../../helpers/preventMessageInputBlur';

import useFlag from '../../../../hooks/useFlag';
import useThrottledCallback from '../../../../hooks/useThrottledCallback';

const ANDROID_KEYBOARD_HIDE_DELAY_MS = 350;
const SWIPE_ANIMATION_DURATION = 150;
// The bubble follows the finger, and a release past this distance replies
const REPLY_SWIPE_THRESHOLD = 3.5 * REM;
// Past the threshold the bubble moves this share of the finger's way, up to the overshoot
const REPLY_SWIPE_RESISTANCE = 0.3;
const REPLY_SWIPE_MAX_OVERSHOOT = 2 * REM;
// The reply arrow grows from this scale as the swipe nears the threshold
const REPLY_ICON_MIN_SCALE = 0.5;
const REPLY_ICON_SELECTOR = '.message-reply-swipe';
const QUICK_REACTION_DOUBLE_TAP_DELAY = 200;
const QUICK_REACTION_AREA_WIDTH = 3 * REM;
const QUICK_REACTION_AREA_HEIGHT = Number(REM);
const GROUP_MESSAGE_HOVER_ATTRIBUTE = 'data-is-document-group-hover';

export default function useOuterHandlers(
  selectMessage: (e?: React.MouseEvent<HTMLDivElement, MouseEvent>, groupedId?: string) => void,
  containerRef: ElementRef<HTMLDivElement>,
  messageId: number,
  isInSelectMode: boolean,
  canReply: boolean,
  isProtected: boolean,
  onContextMenu: (e: React.MouseEvent) => void,
  handleBeforeContextMenu: (e: React.MouseEvent) => void,
  chatId: string,
  isContextMenuShown: boolean,
  quickReactionRef: ElementRef<HTMLDivElement>,
  shouldHandleMouseLeave: boolean,
  getIsMessageListReady?: Signal<boolean>,
  isEphemeral?: boolean,
) {
  const { updateDraftReplyInfo, sendDefaultReaction } = getActions();

  const [isQuickReactionVisible, markQuickReactionVisible, unmarkQuickReactionVisible] = useFlag();
  const [isSwiped, markSwiped, unmarkSwiped] = useFlag();
  const doubleTapTimeoutRef = useRef<number>();

  function handleMouseDown(e: React.MouseEvent<HTMLDivElement, MouseEvent>) {
    preventMessageInputBlur(e);
    handleBeforeContextMenu(e);
  }

  const handleMouseMove = useThrottledCallback((e: React.MouseEvent) => {
    const quickReactionContainer = quickReactionRef.current;
    if (!quickReactionContainer) return;

    const { clientX, clientY } = e;
    const {
      x: quickReactionX, width: quickReactionWidth, y: quickReactionY, height: quickReactionHeight,
    } = quickReactionContainer.getBoundingClientRect();
    const x = quickReactionX + quickReactionWidth / 2;
    const y = quickReactionY + quickReactionHeight / 2;

    const isVisibleX = Math.abs(x - clientX) < QUICK_REACTION_AREA_WIDTH;
    const isVisibleY = Math.abs(y - clientY) < QUICK_REACTION_AREA_HEIGHT;
    if (isVisibleX && isVisibleY) {
      markQuickReactionVisible();
    } else {
      unmarkQuickReactionVisible();
    }
  }, [quickReactionRef], requestMeasure);

  function handleSendQuickReaction(e: React.MouseEvent<HTMLDivElement, MouseEvent>) {
    e.stopPropagation();
    if (isEphemeral) return;
    sendDefaultReaction({
      chatId,
      messageId,
    });
  }

  function handleTap(e: React.MouseEvent<HTMLDivElement, MouseEvent>) {
    if (IS_ANDROID) {
      const target = e.target as HTMLDivElement;
      if (!target.classList.contains('text-content') && !target.classList.contains('Message')) {
        return;
      }

      if (windowSize.getIsKeyboardVisible()) {
        setTimeout(() => {
          onContextMenu(e);
        }, ANDROID_KEYBOARD_HIDE_DELAY_MS);
      } else {
        onContextMenu(e);
      }
    }
  }

  function handleDoubleTap() {
    if (isEphemeral) return;
    sendDefaultReaction({
      chatId,
      messageId,
    });
  }

  function handleClick(e: React.MouseEvent<HTMLDivElement, MouseEvent>) {
    if (isInSelectMode) {
      selectMessage(e);
      return;
    }

    if (!IS_TOUCH_ENV) return;

    if (doubleTapTimeoutRef.current) {
      clearTimeout(doubleTapTimeoutRef.current);
      doubleTapTimeoutRef.current = undefined;
      handleDoubleTap();
      return;
    }

    doubleTapTimeoutRef.current = setTimeout(() => {
      doubleTapTimeoutRef.current = undefined;
      handleTap(e);
    }, QUICK_REACTION_DOUBLE_TAP_DELAY);
  }

  function handleContextMenu(e: React.MouseEvent<HTMLDivElement, MouseEvent>) {
    if (IS_ANDROID) {
      if ((e.target as HTMLElement).matches('a[href]') || isContextMenuShown) {
        return;
      }

      e.preventDefault();
      selectMessage();
    } else {
      onContextMenu(e);
    }
  }

  function handleContainerDoubleClick() {
    if (IS_TOUCH_ENV || !canReply) return;

    if (isEphemeral) {
      updateDraftReplyInfo({
        type: 'ephemeral',
        replyToMsgId: messageId,
      });
      return;
    }

    updateDraftReplyInfo({
      replyToMsgId: messageId,
      replyToPeerId: undefined,
      quoteText: undefined,
      quoteOffset: undefined,
    });
  }

  function stopPropagation(e: React.MouseEvent<HTMLDivElement, MouseEvent>) {
    e.stopPropagation();
  }

  // Swipe to reply: the bubble follows the finger to the left, the reply arrow grows, and a release past the threshold
  // replies. Swiping back below the threshold before the release cancels the reply.
  useEffect(() => {
    if (!IS_TOUCH_ENV || isInSelectMode || !canReply || isContextMenuShown || !getIsMessageListReady?.()) {
      return undefined;
    }

    const container = containerRef.current!;
    let isActive = false;
    let startOffset = 0;
    let distance = 0;
    let isPastThreshold = false;
    let isMoveScheduled = false;

    function applyDistance() {
      const offset = distance <= REPLY_SWIPE_THRESHOLD ? distance : REPLY_SWIPE_THRESHOLD + Math.min(
        (distance - REPLY_SWIPE_THRESHOLD) * REPLY_SWIPE_RESISTANCE, REPLY_SWIPE_MAX_OVERSHOOT,
      );
      const progress = Math.min(1, distance / REPLY_SWIPE_THRESHOLD);
      container.style.transform = `translateX(${-offset}px)`;

      const icon = container.querySelector<HTMLElement>(REPLY_ICON_SELECTOR);
      if (icon) {
        icon.style.opacity = String(progress);
        icon.style.transform = `scale(${REPLY_ICON_MIN_SCALE + (1 - REPLY_ICON_MIN_SCALE) * progress})`;
      }
    }

    function resetStyles() {
      container.style.transition = '';
      container.style.transform = '';
    }

    const releaseEvents = captureEvents(container, {
      selectorToPreventScroll: '.MessageList',
      excludedClosestSelector: '.no-word-wrap',
      withNativeDrag: true,
      onSwipe: (e, direction, { dragOffsetX }) => {
        // The swipe back from the chat may have taken the touch first
        const owner = getTouchOwner();
        if (direction !== SwipeDirection.Left || (owner && owner !== container)) return false;

        isActive = true;
        startOffset = dragOffsetX;
        distance = 0;
        isPastThreshold = false;
        markSwiped();
        requestMutation(() => {
          container.style.transition = 'none';
        });

        return true;
      },
      onDrag: (e, captureEvent, { dragOffsetX }) => {
        if (!isActive) return;

        distance = Math.max(0, startOffset - dragOffsetX);
        const isPast = distance >= REPLY_SWIPE_THRESHOLD;
        if (isPast && !isPastThreshold) {
          triggerHaptic('light');
        }
        isPastThreshold = isPast;

        if (isMoveScheduled) return;
        isMoveScheduled = true;
        requestMutation(() => {
          isMoveScheduled = false;
          if (isActive) applyDistance();
        });
      },
      onRelease: (e) => {
        if (!isActive) return;

        isActive = false;
        if (isPastThreshold && e.type !== 'touchcancel') {
          if (isEphemeral) {
            updateDraftReplyInfo({
              type: 'ephemeral',
              replyToMsgId: messageId,
            });
          } else {
            updateDraftReplyInfo({ replyToMsgId: messageId });
          }
        }

        distance = 0;
        requestMutation(() => {
          container.style.transition = `transform ${SWIPE_ANIMATION_DURATION}ms ease-out`;
          applyDistance();
        });
        setTimeout(() => {
          if (isActive) return;

          unmarkSwiped();
          requestMutation(resetStyles);
        }, SWIPE_ANIMATION_DURATION);
      },
    });

    return () => {
      releaseEvents();
      if (!isActive) return;

      isActive = false;
      unmarkSwiped();
      requestMutation(resetStyles);
    };
  }, [
    containerRef, isInSelectMode, messageId, markSwiped, unmarkSwiped, canReply, isContextMenuShown,
    getIsMessageListReady, isEphemeral,
  ]);

  function handleMouseLeave(e: React.MouseEvent<HTMLDivElement>) {
    // Because `mousemove` event is throttled, we need to also throttle `mouseleave` event,
    // so the order of events is preserved
    requestMeasure(unmarkQuickReactionVisible);
    if (shouldHandleMouseLeave) handleDocumentGroupMouseLeave(e);
  }

  return {
    handleMouseDown: !isInSelectMode ? handleMouseDown : undefined,
    handleClick,
    handleContextMenu: !isInSelectMode ? handleContextMenu : (isProtected ? stopEvent : undefined),
    handleDoubleClick: !isInSelectMode ? handleContainerDoubleClick : undefined,
    handleContentDoubleClick: !IS_TOUCH_ENV ? stopPropagation : undefined,
    handleMouseMove,
    handleSendQuickReaction,
    handleMouseLeave,
    isSwiped,
    isQuickReactionVisible,
    handleDocumentGroupMouseEnter,
  };
}

function handleDocumentGroupMouseEnter(e: React.MouseEvent<HTMLDivElement>) {
  const lastGroupElement = getLastElementInDocumentGroup(e.currentTarget);
  if (lastGroupElement) {
    lastGroupElement.setAttribute(GROUP_MESSAGE_HOVER_ATTRIBUTE, '');
  }
}

function handleDocumentGroupMouseLeave(e: React.MouseEvent<HTMLDivElement>) {
  const lastGroupElement = getLastElementInDocumentGroup(e.currentTarget);
  if (lastGroupElement) {
    lastGroupElement.removeAttribute(GROUP_MESSAGE_HOVER_ATTRIBUTE);
  }
}

function getLastElementInDocumentGroup(element: Element) {
  let current: Element | null = element;

  do {
    current = current.nextElementSibling;
  } while (current && !current.classList.contains('last-in-document-group'));

  return current;
}
