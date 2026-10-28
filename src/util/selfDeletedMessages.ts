import type { MessageKey } from './keys/messageKey';

import { buildMessageKey } from './keys/messageKey';

// Deletions requested by the user arrive through the same server update as deletions by others
const SELF_DELETED_KEYS = new Set<MessageKey>();
const SELF_DELETED_KEYS_LIMIT = 1000;

export function rememberSelfDeletedMessages(chatId: string, messageIds: number[]) {
  messageIds.forEach((id) => {
    SELF_DELETED_KEYS.add(buildMessageKey(chatId, id));
  });

  const excessCount = SELF_DELETED_KEYS.size - SELF_DELETED_KEYS_LIMIT;
  if (excessCount <= 0) return;

  Array.from(SELF_DELETED_KEYS).slice(0, excessCount).forEach((key) => {
    SELF_DELETED_KEYS.delete(key);
  });
}

export function consumeSelfDeletedMessage(chatId: string, messageId: number) {
  return SELF_DELETED_KEYS.delete(buildMessageKey(chatId, messageId));
}
