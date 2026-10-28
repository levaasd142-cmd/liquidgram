import { TELEGRAM_API_HASH, TELEGRAM_API_ID } from '../config';

export type ApiCredentials = {
  apiId: number;
  apiHash: string;
};

const API_CREDENTIALS_KEY = 'lg-api-credentials';
const API_CREDENTIALS_REJECTED_KEY = 'lg-api-credentials-rejected';
const API_HASH_REGEX = /^[a-f0-9]{32}$/i;

let storageListener: ((e: StorageEvent) => void) | undefined;

// Builds without `.env` credentials ask the user for their own pair from my.telegram.org
export function getApiCredentials(): ApiCredentials | undefined {
  if (TELEGRAM_API_ID && TELEGRAM_API_HASH) {
    return { apiId: TELEGRAM_API_ID, apiHash: TELEGRAM_API_HASH };
  }

  return getStoredApiCredentials();
}

export function storeApiCredentials(credentials: ApiCredentials) {
  localStorage.setItem(API_CREDENTIALS_KEY, JSON.stringify(credentials));
  localStorage.removeItem(API_CREDENTIALS_REJECTED_KEY);
}

// Forgets credentials refused by Telegram so the login screen asks for them again
export function rejectStoredApiCredentials() {
  if (!localStorage.getItem(API_CREDENTIALS_KEY)) return;

  localStorage.removeItem(API_CREDENTIALS_KEY);
  localStorage.setItem(API_CREDENTIALS_REJECTED_KEY, '1');
}

export function getAreApiCredentialsRejected() {
  return Boolean(localStorage.getItem(API_CREDENTIALS_REJECTED_KEY));
}

export function checkApiCredentials(apiId: number, apiHash: string) {
  return Number.isSafeInteger(apiId) && apiId > 0 && API_HASH_REGEX.test(apiHash);
}

// Credentials can be entered in a tab that does not own the API connection
export function waitForStoredApiCredentials(onStored: NoneToVoidFunction) {
  if (storageListener) return;

  storageListener = (e: StorageEvent) => {
    if (e.key !== API_CREDENTIALS_KEY || !getStoredApiCredentials()) return;

    window.removeEventListener('storage', storageListener!);
    storageListener = undefined;
    onStored();
  };

  window.addEventListener('storage', storageListener);
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
