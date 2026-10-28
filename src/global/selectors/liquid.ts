import type { ApiMessage } from '../../api/types';
import type { ThreadId } from '../../types';
import type { GlobalState } from '../types';
import { MAIN_THREAD_ID } from '../../api/types';

import { selectThreadIdFromMessage } from './threads';

const INITIAL_LIQUID_STATE: NonNullable<GlobalState['liquid']> = {
  deletedMessagesByChatId: {},
  editHistoryByChatId: {},
};

export function selectLiquidState<T extends GlobalState>(global: T) {
  return global.liquid || INITIAL_LIQUID_STATE;
}

export function selectMessageEditHistory<T extends GlobalState>(global: T, chatId: string, messageId: number) {
  return global.liquid?.editHistoryByChatId[chatId]?.[messageId];
}

// Picks preserved messages located inside the id range of a loaded history slice
export function selectLiquidDeletedMessagesForSlice<T extends GlobalState>(
  global: T, chatId: string, threadId: ThreadId, sliceMessages: ApiMessage[], isLatestSlice: boolean,
): ApiMessage[] {
  const byId = global.liquid?.deletedMessagesByChatId[chatId];
  if (!byId || !sliceMessages.length) return [];

  const sliceIds = sliceMessages.map(({ id }) => id);
  const minId = Math.min(...sliceIds);
  const maxId = isLatestSlice ? Infinity : Math.max(...sliceIds);

  return Object.values(byId).filter((message) => (
    message.id >= minId && message.id <= maxId
    && (threadId === MAIN_THREAD_ID || selectThreadIdFromMessage(global, message) === threadId)
  ));
}
