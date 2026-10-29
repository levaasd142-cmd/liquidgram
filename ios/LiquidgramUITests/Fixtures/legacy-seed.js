// Seeds data that only the migration can carry over, in the loopback version of the app (http://127.0.0.1:47821), for
// `TransportTests/testLegacyDataMovesToAppOrigin`. `Tools/seed-legacy-app.sh` injects it at document start through
// `LIQUIDGRAM_TEST_USER_SCRIPT`, after `offline-api.js` and `demo-account.js`: a `localStorage` marker and an
// IndexedDB record with every kind of value that JSON cannot hold. `migration-check.js` reads them back in the app's
// origin.
(() => {
  'use strict';

  const MARKER_KEY = 'liquidgram-test-legacy-marker';
  const DATABASE_NAME = 'liquidgram-test-legacy';
  const STORE_NAME = 'values';

  if (location.origin !== 'http://127.0.0.1:47821') return;

  localStorage.setItem(MARKER_KEY, 'loopback');

  const request = indexedDB.open(DATABASE_NAME, 1);
  request.onupgradeneeded = () => {
    request.result.createObjectStore(STORE_NAME);
  };
  request.onsuccess = () => {
    const database = request.result;
    const transaction = database.transaction(STORE_NAME, 'readwrite');
    transaction.objectStore(STORE_NAME).put({
      blob: new Blob([new Uint8Array([1, 2, 3])], { type: 'image/jpeg' }),
      buffer: new Uint8Array([250, 251, 252]).buffer,
      view: new Int16Array([-2, 300]),
      date: new Date(1700000000000),
      big: 9007199254740993n,
      map: new Map([['key', new Set(['a', 2])]]),
      nothing: undefined,
      notANumber: NaN,
      text: 'Привет',
    }, 'typed');
    transaction.oncomplete = () => database.close();
  };
})();
