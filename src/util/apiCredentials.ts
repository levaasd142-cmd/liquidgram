import { TELEGRAM_API_HASH, TELEGRAM_API_ID } from '../config';

export type ApiCredentials = {
  apiId: number;
  apiHash: string;
};

const API_CREDENTIALS_KEY = 'lg-api-credentials';
const API_HASH_REGEX = /^[a-f0-9]{32}$/i;

// Builds without `.env` credentials ask the user for their own pair from my.telegram.org
export function getApiCredentials(): ApiCredentials | undefined {
  if (TELEGRAM_API_ID && TELEGRAM_API_HASH) {
    return { apiId: TELEGRAM_API_ID, apiHash: TELEGRAM_API_HASH };
  }

  return getStoredApiCredentials();
}

export function storeApiCredentials(credentials: ApiCredentials) {
  localStorage.setItem(API_CREDENTIALS_KEY, JSON.stringify(credentials));
}

export function checkApiCredentials(apiId: number, apiHash: string) {
  return Number.isSafeInteger(apiId) && apiId > 0 && API_HASH_REGEX.test(apiHash);
}

function getStoredApiCredentials(): ApiCredentials | undefined {
  try {
    const json = localStorage.getItem(API_CREDENTIALS_KEY);
    if (!json) return undefined;

    const { apiId, apiHash } = JSON.parse(json) as Partial<ApiCredentials>;
    if (apiId === undefined || apiHash === undefined || !checkApiCredentials(apiId, apiHash)) return undefined;

    return { apiId, apiHash };
  } catch {
    return undefined;
  }
}
