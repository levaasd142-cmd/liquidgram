// Body of the async function that `TestHooks` runs in the page for `TransportTests/testLegacyDataMovesToAppOrigin`,
// through `LIQUIDGRAM_TEST_SELFTEST_SCRIPT`, after the loopback version of the app ran with the demo account and
// `legacy-seed.js`. It checks that `LegacyDataMigration` moved the session, the API keys, the web app's cached state
// and the seeded values into liquidgram-web://app, and returns a JSON report in the form of `selftest.js`.
'use strict';

const CHECK_TIMEOUT_MS = 10000;
const API_CREDENTIALS = { apiId: 1, apiHash: '0123456789abcdef0123456789abcdef' };
const DEMO_USER_ID = '100000';
const DEMO_CHAT_ID = '100101';

const checks = [];

await runCheck('appOrigin', () => {
  assert(location.origin === 'liquidgram-web://app', `the origin is ${location.origin}`);
  return location.origin;
});

await runCheck('migrationOutcome', () => {
  const outcome = typeof migrationOutcome === 'string' ? migrationOutcome : '';
  assert(outcome.startsWith('moved '), `the migration says: ${outcome || 'nothing'}`);
  return outcome;
});

await runCheck('apiCredentials', () => {
  const credentials = JSON.parse(localStorage.getItem('lg-api-credentials') || 'null');
  assert(credentials && credentials.apiId === API_CREDENTIALS.apiId && credentials.apiHash === API_CREDENTIALS.apiHash,
    `lg-api-credentials is ${JSON.stringify(credentials)}`);
  return 'the API keys of the loopback version';
});

await runCheck('session', () => {
  const account = JSON.parse(localStorage.getItem('account1') || 'null');
  assert(account && account.userId === DEMO_USER_ID && account.dcId === 2, `account1 is ${JSON.stringify(account)}`);
  return `account1 of user ${account.userId} on DC ${account.dcId}`;
});

await runCheck('marker', () => {
  const marker = localStorage.getItem('liquidgram-test-legacy-marker');
  assert(marker === 'loopback', `the marker is ${marker}`);
  return 'the localStorage marker of legacy-seed.js';
});

await runCheck('typedValues', async () => {
  const value = await readRecord('liquidgram-test-legacy', 'values', 'typed');
  assert(value, 'no record');
  assert(value.blob instanceof Blob && value.blob.type === 'image/jpeg', 'the Blob or its type');
  assert(String(new Uint8Array(await value.blob.arrayBuffer())) === '1,2,3', 'the bytes of the Blob');
  assert(value.buffer instanceof ArrayBuffer && String(new Uint8Array(value.buffer)) === '250,251,252', 'the ArrayBuffer');
  assert(value.view instanceof Int16Array && String(value.view) === '-2,300', 'the Int16Array');
  assert(value.date instanceof Date && value.date.getTime() === 1700000000000, 'the Date');
  assert(value.big === 9007199254740993n, 'the BigInt');
  assert(value.map instanceof Map && value.map.get('key') instanceof Set && value.map.get('key').has(2), 'the Map');
  assert('nothing' in value && value.nothing === undefined, 'the undefined property');
  assert(Number.isNaN(value.notANumber), 'NaN');
  assert(value.text === 'Привет', 'the text');
  return 'Blob, ArrayBuffer, Int16Array, Date, BigInt, Map, Set, undefined and NaN';
});

await runCheck('cachedState', async () => {
  const state = await readRecord('tt-data', 'store', 'tt-global-state');
  assert(state && state.chats && state.chats.byId && state.chats.byId[DEMO_CHAT_ID],
    'the cached state of the web app has no chats');
  return `the cached state with ${Object.keys(state.chats.byId).length} chats`;
});

return JSON.stringify({
  ok: checks.every((check) => check.ok),
  checks,
  info: { url: location.href, localStorageKeys: Object.keys(localStorage).sort() },
});

function readRecord(databaseName, storeName, key) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(databaseName);
    request.onsuccess = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(storeName)) {
        database.close();
        resolve(undefined);
        return;
      }
      const get = database.transaction(storeName, 'readonly').objectStore(storeName).get(key);
      get.onsuccess = () => {
        database.close();
        resolve(get.result);
      };
      get.onerror = () => reject(get.error);
    };
    request.onerror = () => reject(request.error);
  });
}

async function runCheck(name, check) {
  try {
    const detail = await withTimeout(Promise.resolve().then(check));
    checks.push({ name, ok: true, detail: String(detail) });
  } catch (err) {
    checks.push({ name, ok: false, detail: err instanceof Error ? `${err.name}: ${err.message}` : String(err) });
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function withTimeout(promise) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(`no result in ${CHECK_TIMEOUT_MS} ms`)), CHECK_TIMEOUT_MS);
    promise.then((value) => {
      clearTimeout(timeout);
      resolve(value);
    }, (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}
