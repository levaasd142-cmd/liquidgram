// Liquidgram iOS: moves the website data of version 1, which served the web app at http://127.0.0.1:47821, into the
// app's origin, liquidgram-web://app. `LegacyDataMigration.swift` runs this file with `callAsyncJavaScript` in a hidden
// web view, on an empty page of each origin: `exportLegacyData()` reads everything in `localStorage` and IndexedDB,
// and `importLegacyData(payload)` writes it. The payload is JSON, which holds no Blobs, ArrayBuffers, typed arrays,
// Dates, BigInts, Maps, Sets, `undefined` or numbers like NaN, so these travel as objects tagged with `$lg`; a plain
// object that has that key itself is wrapped as well. A record that cannot be copied, such as one with a `CryptoKey`,
// is left out and reported. Plain ES2020, so that every iOS 16 `WKWebView` runs it.

const TAG = '$lg';
const VIEW_TYPES = {
  Int8Array,
  Uint8Array,
  Uint8ClampedArray,
  Int16Array,
  Uint16Array,
  Int32Array,
  Uint32Array,
  Float32Array,
  Float64Array,
  BigInt64Array,
  BigUint64Array,
  DataView,
};
// The web app keeps a Telegram session under `account<slot>`, and under `user_auth` in its first versions
const SESSION_KEY = /^(account\d+|user_auth)$/;
// Spreading a large buffer into `String.fromCharCode` overflows the call stack
const BASE64_CHUNK_LENGTH = 0x8000;
const MAX_KEY_DESCRIPTION_LENGTH = 80;

async function exportLegacyData() {
  const items = {};
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    items[key] = localStorage.getItem(key);
  }

  const skipped = [];
  const databases = [];
  const infos = typeof indexedDB.databases === 'function' ? await indexedDB.databases() : [];
  for (const { name } of infos) {
    if (name) databases.push(await exportDatabase(name, skipped));
  }

  return {
    payload: JSON.stringify({ localStorage: items, databases }),
    localStorageCount: Object.keys(items).length,
    databaseCount: databases.length,
    recordCount: databases.reduce((count, database) => count + countRecords(database), 0),
    skipped,
  };
}

async function importLegacyData(payloadJson) {
  const { localStorage: items, databases } = JSON.parse(payloadJson);
  // A session that the app's origin has already, such as after the user signed in again, wins
  if (Object.keys(localStorage).some((key) => SESSION_KEY.test(key))) {
    return { hasSession: true };
  }

  let recordCount = 0;
  for (const database of databases) {
    recordCount += await importDatabase(database);
  }
  // The session comes last, so it never exists without the data that belongs to it
  Object.keys(items).forEach((key) => {
    localStorage.setItem(key, items[key]);
  });

  return { hasSession: false, localStorageCount: Object.keys(items).length, recordCount };
}

async function exportDatabase(name, skipped) {
  const database = await openDatabase(name);
  try {
    const stores = [];
    for (const storeName of Array.from(database.objectStoreNames)) {
      stores.push(await exportStore(database, storeName, skipped));
    }
    return { name, version: database.version, stores };
  } finally {
    database.close();
  }
}

async function exportStore(database, storeName, skipped) {
  const store = database.transaction(storeName, 'readonly').objectStore(storeName);
  // The indexes can only be read while the transaction is active
  const description = {
    name: storeName,
    keyPath: store.keyPath,
    autoIncrement: store.autoIncrement,
    indexes: Array.from(store.indexNames, (indexName) => {
      const index = store.index(indexName);
      return {
        name: indexName, keyPath: index.keyPath, unique: index.unique, multiEntry: index.multiEntry,
      };
    }),
  };
  const [keys, values] = await Promise.all([requestResult(store.getAllKeys()), requestResult(store.getAll())]);

  const blobs = [];
  const records = [];
  keys.forEach((key, i) => {
    try {
      records.push([encodeValue(key, blobs), encodeValue(values[i], blobs)]);
    } catch (err) {
      skipped.push(`${database.name}/${storeName}/${describeKey(key)}: ${err.message}`);
    }
  });
  await Promise.all(blobs.map(async ({ target, blob }) => {
    target.value = encodeBytes(new Uint8Array(await blob.arrayBuffer()));
  }));

  return { ...description, records };
}

async function importDatabase({ name, version, stores }) {
  let database = await openDatabase(name, version, (upgradeDatabase) => createStores(upgradeDatabase, stores))
    .catch((err) => (err && err.name === 'VersionError' ? openDatabase(name) : Promise.reject(err)));
  const missingStores = stores.filter((store) => !database.objectStoreNames.contains(store.name));
  if (missingStores.length) {
    const nextVersion = database.version + 1;
    database.close();
    database = await openDatabase(name, nextVersion, (upgradeDatabase) => createStores(upgradeDatabase, missingStores));
  }

  try {
    if (!stores.length) return 0;

    const transaction = database.transaction(stores.map((store) => store.name), 'readwrite');
    let count = 0;
    stores.forEach((store) => {
      const objectStore = transaction.objectStore(store.name);
      store.records.forEach(([key, value]) => {
        // A store with a key path takes the key from the value
        if (store.keyPath === null) {
          objectStore.put(decodeValue(value), decodeValue(key));
        } else {
          objectStore.put(decodeValue(value));
        }
        count++;
      });
    });
    await transactionDone(transaction);
    return count;
  } finally {
    database.close();
  }
}

function createStores(database, stores) {
  stores.forEach((store) => {
    if (database.objectStoreNames.contains(store.name)) return;

    const objectStore = database.createObjectStore(store.name, {
      keyPath: store.keyPath, autoIncrement: store.autoIncrement,
    });
    store.indexes.forEach((index) => {
      objectStore.createIndex(index.name, index.keyPath, { unique: index.unique, multiEntry: index.multiEntry });
    });
  });
}

function openDatabase(name, version, upgrade) {
  return new Promise((resolve, reject) => {
    const request = version === undefined ? indexedDB.open(name) : indexedDB.open(name, version);
    request.onupgradeneeded = () => {
      if (upgrade) upgrade(request.result);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function requestResult(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function transactionDone(transaction) {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error || new Error('The transaction was aborted'));
  });
}

function countRecords(database) {
  return database.stores.reduce((count, store) => count + store.records.length, 0);
}

// Blobs are read afterwards, so `blobs` collects them with the object that receives their bytes
function encodeValue(value, blobs, path = new Set()) {
  switch (typeof value) {
    case 'undefined':
      return { [TAG]: 'undefined' };
    case 'number':
      if (Object.is(value, -0)) return { [TAG]: 'number', value: '-0' };
      return Number.isFinite(value) ? value : { [TAG]: 'number', value: String(value) };
    case 'bigint':
      return { [TAG]: 'bigint', value: value.toString() };
    case 'string':
    case 'boolean':
      return value;
    case 'object':
      break;
    default:
      throw new TypeError(`A ${typeof value} cannot be copied`);
  }
  if (value === null) return value;
  if (path.has(value)) throw new TypeError('A value that contains itself cannot be copied');

  path.add(value);
  try {
    return encodeObject(value, blobs, path);
  } finally {
    path.delete(value);
  }
}

function encodeObject(value, blobs, path) {
  if (Array.isArray(value)) return Array.from(value, (item) => encodeValue(item, blobs, path));
  if (value instanceof Date) return { [TAG]: 'date', value: String(value.getTime()) };
  if (value instanceof RegExp) return { [TAG]: 'regexp', source: value.source, flags: value.flags };
  if (value instanceof ArrayBuffer) return { [TAG]: 'arrayBuffer', value: encodeBytes(new Uint8Array(value)) };
  if (ArrayBuffer.isView(value)) {
    const type = Object.keys(VIEW_TYPES).find((name) => value instanceof VIEW_TYPES[name]);
    if (!type) throw new TypeError('An unknown view cannot be copied');
    const bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    return { [TAG]: 'view', type, value: encodeBytes(bytes) };
  }
  if (value instanceof Blob) {
    const target = value instanceof File
      ? {
        [TAG]: 'file', type: value.type, name: value.name, lastModified: value.lastModified,
      }
      : { [TAG]: 'blob', type: value.type };
    blobs.push({ target, blob: value });
    return target;
  }
  if (value instanceof Map) {
    return {
      [TAG]: 'map',
      value: Array.from(value, ([key, item]) => [encodeValue(key, blobs, path), encodeValue(item, blobs, path)]),
    };
  }
  if (value instanceof Set) return { [TAG]: 'set', value: Array.from(value, (item) => encodeValue(item, blobs, path)) };
  if (value instanceof Error) return { [TAG]: 'error', name: value.name, message: value.message };
  if (value instanceof Boolean || value instanceof Number || value instanceof String) {
    return encodeValue(value.valueOf(), blobs, path);
  }

  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) {
    throw new TypeError(`A ${Object.prototype.toString.call(value)} cannot be copied`);
  }
  const result = {};
  Object.keys(value).forEach((key) => {
    result[key] = encodeValue(value[key], blobs, path);
  });
  return Object.prototype.hasOwnProperty.call(value, TAG) ? { [TAG]: 'object', value: result } : result;
}

function decodeValue(value) {
  if (Array.isArray(value)) return value.map(decodeValue);
  if (!value || typeof value !== 'object') return value;

  if (!Object.prototype.hasOwnProperty.call(value, TAG)) return decodeProperties(value);

  switch (value[TAG]) {
    case 'undefined':
      return undefined;
    case 'number':
      return Number(value.value);
    case 'bigint':
      return BigInt(value.value);
    case 'date':
      return new Date(Number(value.value));
    case 'regexp':
      return new RegExp(value.source, value.flags);
    case 'arrayBuffer':
      return decodeBytes(value.value).buffer;
    case 'view': {
      const { buffer } = decodeBytes(value.value);
      const View = VIEW_TYPES[value.type];
      return View === DataView ? new DataView(buffer) : new View(buffer);
    }
    case 'blob':
      return new Blob([decodeBytes(value.value)], { type: value.type });
    case 'file':
      return new File([decodeBytes(value.value)], value.name, { type: value.type, lastModified: value.lastModified });
    case 'map':
      return new Map(value.value.map(([key, item]) => [decodeValue(key), decodeValue(item)]));
    case 'set':
      return new Set(value.value.map(decodeValue));
    case 'error': {
      const error = new Error(value.message);
      error.name = value.name;
      return error;
    }
    case 'object':
      return decodeProperties(value.value);
    default:
      throw new TypeError(`Unknown tag ${value[TAG]}`);
  }
}

function decodeProperties(value) {
  const result = {};
  Object.keys(value).forEach((key) => {
    result[key] = decodeValue(value[key]);
  });
  return result;
}

function encodeBytes(bytes) {
  if (typeof bytes.toBase64 === 'function') return bytes.toBase64();

  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += BASE64_CHUNK_LENGTH) {
    binary += String.fromCharCode.apply(undefined, bytes.subarray(offset, offset + BASE64_CHUNK_LENGTH));
  }
  return btoa(binary);
}

function decodeBytes(base64) {
  if (typeof Uint8Array.fromBase64 === 'function') return Uint8Array.fromBase64(base64);

  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function describeKey(key) {
  try {
    return String(key).slice(0, MAX_KEY_DESCRIPTION_LENGTH);
  } catch (err) {
    return Object.prototype.toString.call(key);
  }
}
