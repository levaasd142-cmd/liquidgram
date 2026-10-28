import type { ApiMessage } from '../../api/types';
import type { LiquidEditVersion } from '../../types';
import type { GlobalState } from '../types';

import { selectLiquidState } from '../selectors/liquid';

const DELETED_MESSAGES_PER_CHAT_LIMIT = 300;
const EDIT_VERSIONS_PER_MESSAGE_LIMIT = 20;
const EDITED_MESSAGES_PER_CHAT_LIMIT = 300;

export function addLiquidDeletedMessages<T extends GlobalState>(global: T, chatId: string, messages: ApiMessage[]): T {
  const liquid = selectLiquidState(global);
  const byId = { ...liquid.deletedMessagesByChatId[chatId] };
  messages.forEach((message) => {
    byId[message.id] = message;
  });

  return {
    ...global,
    liquid: {
      ...liquid,
      deletedMessagesByChatId: {
        ...liquid.deletedMessagesByChatId,
        [chatId]: trimOldestIds(byId, DELETED_MESSAGES_PER_CHAT_LIMIT),
      },
    },
  };
}

export function removeLiquidDeletedMessages<T extends GlobalState>(global: T, chatId: string, ids: number[]): T {
  const liquid = selectLiquidState(global);
  const byId = liquid.deletedMessagesByChatId[chatId];
  if (!byId || !ids.some((id) => byId[id])) return global;

  return {
    ...global,
    liquid: {
      ...liquid,
      deletedMessagesByChatId: {
        ...liquid.deletedMessagesByChatId,
        [chatId]: omitIds(byId, ids),
      },
    },
  };
}

export function clearLiquidChat<T extends GlobalState>(global: T, chatId: string): T {
  const { liquid } = global;
  if (!liquid || (!liquid.deletedMessagesByChatId[chatId] && !liquid.editHistoryByChatId[chatId])) return global;

  const deletedMessagesByChatId = { ...liquid.deletedMessagesByChatId };
  const editHistoryByChatId = { ...liquid.editHistoryByChatId };
  delete deletedMessagesByChatId[chatId];
  delete editHistoryByChatId[chatId];

  return {
    ...global,
    liquid: {
      deletedMessagesByChatId,
      editHistoryByChatId,
    },
  };
}

export function addLiquidEditVersion<T extends GlobalState>(
  global: T, chatId: string, messageId: number, version: LiquidEditVersion,
): T {
  const liquid = selectLiquidState(global);
  const byId = liquid.editHistoryByChatId[chatId] || {};
  const versions = [...(byId[messageId] || []), version].slice(-EDIT_VERSIONS_PER_MESSAGE_LIMIT);

  return {
    ...global,
    liquid: {
      ...liquid,
      editHistoryByChatId: {
        ...liquid.editHistoryByChatId,
        [chatId]: trimOldestIds({ ...byId, [messageId]: versions }, EDITED_MESSAGES_PER_CHAT_LIMIT),
      },
    },
  };
}

function trimOldestIds<V>(byId: Record<number, V>, limit: number) {
  const ids = Object.keys(byId).map(Number);
  if (ids.length <= limit) return byId;

  ids.sort((a, b) => a - b);
  return omitIds(byId, ids.slice(0, ids.length - limit));
}

function omitIds<V>(byId: Record<number, V>, ids: number[]) {
  const idsToOmit = new Set(ids);
  return Object.entries(byId).reduce((acc, [id, value]) => {
    if (!idsToOmit.has(Number(id))) acc[Number(id)] = value;
    return acc;
  }, {} as Record<number, V>);
}
