// Body of the async function that `TestHooks` runs in the page for `TransportTests/testMediaStreamsFromPage`, through
// `LIQUIDGRAM_TEST_SELFTEST_SCRIPT`. It checks how videos and music stream through
// `liquidgram-web://app/progressive/`, where `ProgressiveMediaStream.swift` answers the range requests of media
// elements with bytes it gets from the page's `window.__liquidgramNative.loadMediaPart`. It returns a JSON report in
// the form of `selftest.js`.
//
// The first check goes through the whole chain of the web app: the stream asks the web app's `loadMediaPart`, which
// downloads through its API from the worker of `media-api.js`. The other checks put a synthetic `loadMediaPart` in its
// place, which serves test files with a delay per part, like a network, and records what the stream asked for.
'use strict';

const CHECK_TIMEOUT_MS = 30000;
const PART_LENGTH = 512 * 1024;
const MAX_CONCURRENT_LOADS = 4;
// The media data of `nojs.mp4` moves behind this much padding, so the video spans parts
const VIDEO_PADDING = 3 * PART_LENGTH;
const VIDEO_PART_DELAY_MS = 300;
const AUDIO_SECONDS = 30;
const AUDIO_SAMPLE_RATE = 44100;
const AUDIO_PART_DELAY_MS = 600;
const AUDIO_SEEK_FRACTION = 0.8;
const FETCH_PART_DELAY_MS = 20;
const SYNTHETIC_LENGTH = 1300000;

const checks = [];
const info = { migrationOutcome: typeof migrationOutcome === 'string' ? migrationOutcome : undefined };
const native = window.__liquidgramNative;

await runCheck('appOrigin', () => {
  assert(location.origin === 'liquidgram-web://app', `the origin is ${location.origin}`);
  return location.origin;
});

await runCheck('loadMediaPartRegistered', () => {
  assert(native && typeof native.loadMediaPart === 'function', 'the web app did not set `loadMediaPart`');
  assert(window.__liquidgramTestMedia, '`media-api.js` did not run');
  return 'the web app set `window.__liquidgramNative.loadMediaPart`';
});

const nojs = new Uint8Array(await (await fetch('./nojs.mp4', { cache: 'no-store' })).arrayBuffer());
const paddedVideo = padMp4(nojs, VIDEO_PADDING);

await runCheck('webAppChain', async () => {
  const hash = 'document4242424242';
  window.__liquidgramTestMedia.files[hash] = { bytes: paddedVideo, mimeType: 'video/mp4', delay: VIDEO_PART_DELAY_MS };
  const result = await playMedia('video', makeUrl(hash, paddedVideo.length, 'video/mp4'), { seekTo: 2 });
  const parts = window.__liquidgramTestMedia.requests.filter((request) => request.hash === hash)
    .map((request) => request.start / PART_LENGTH);
  assert(parts.length, 'the web app downloaded no part');
  info.webAppChain = { ...result, parts };
  return `played ${describePlayback(result)}; the web app downloaded parts ${parts.join(', ')} of `
    + `${countParts(paddedVideo.length)}`;
});

const appLoader = native.loadMediaPart;
const provider = makeProvider();
native.loadMediaPart = provider.load;
try {
  await runRangeChecks();
  await runMediaChecks();
} finally {
  native.loadMediaPart = appLoader;
}

return JSON.stringify({ ok: checks.every((check) => check.ok), checks, info });

async function runRangeChecks() {
  const bytes = makeBytes(SYNTHETIC_LENGTH, 7);
  provider.files.synthetic = { bytes, mimeType: 'video/mp4', delay: FETCH_PART_DELAY_MS };
  const url = makeUrl('synthetic', bytes.length, 'video/mp4');
  const undeclaredUrl = './progressive/synthetic';

  await runCheck('probeRange', async () => {
    const response = await fetch(url, { headers: { Range: 'bytes=0-1' }, cache: 'no-store' });
    await expectRange(response, bytes, 0, 2);
    expectHeader(response, 'content-type', 'video/mp4');
    expectHeader(response, 'accept-ranges', 'bytes');
    expectHeader(response, 'x-content-type-options', 'nosniff');
    expectHeader(response, 'content-security-policy', 'sandbox');
    return '206 bytes 0-1, video/mp4, nosniff, sandbox';
  });
  await runCheck('openRange', async () => {
    await expectRange(await fetchRange(url, 'bytes=0-'), bytes, 0, PART_LENGTH);
    return `206 with the first ${PART_LENGTH} bytes`;
  });
  await runCheck('unalignedRanges', async () => {
    await expectRange(await fetchRange(url, 'bytes=1000-'), bytes, 1000, 1000 + PART_LENGTH);
    await expectRange(await fetchRange(url, 'bytes=524000-524600'), bytes, 524000, 524601);
    await expectRange(await fetchRange(url, 'bytes=1299990-'), bytes, 1299990, SYNTHETIC_LENGTH);
    return 'across a part boundary and at the end of the file';
  });
  await runCheck('suffixRanges', async () => {
    await expectRange(await fetchRange(url, 'bytes=-100'), bytes, SYNTHETIC_LENGTH - 100, SYNTHETIC_LENGTH);
    await expectRange(await fetchRange(undeclaredUrl, 'bytes=-100'), bytes, SYNTHETIC_LENGTH - 100, SYNTHETIC_LENGTH);
    return 'with and without the size in the URL';
  });
  await runCheck('beyondEnd', async () => {
    const response = await fetchRange(url, `bytes=${SYNTHETIC_LENGTH}-`);
    assert(response.status === 416, `status ${response.status}`);
    expectHeader(response, 'content-range', `bytes */${SYNTHETIC_LENGTH}`);
    return `416 with bytes */${SYNTHETIC_LENGTH}`;
  });
  await runCheck('wholeFile', async () => {
    const response = await fetch(url, { cache: 'no-store' });
    assert(response.status === 200, `status ${response.status}`);
    expectHeader(response, 'content-length', String(SYNTHETIC_LENGTH));
    expectBytes(new Uint8Array(await response.arrayBuffer()), bytes, 0, SYNTHETIC_LENGTH);
    const head = await fetch(url, { method: 'HEAD', cache: 'no-store' });
    assert(head.status === 200, `HEAD status ${head.status}`);
    expectHeader(head, 'content-length', String(SYNTHETIC_LENGTH));
    return 'GET without a range is 200 with every part in order; HEAD gives the size';
  });
  await runCheck('parallelRanges', async () => {
    const otherBytes = makeBytes(5 * PART_LENGTH + 123, 9);
    provider.files.parallel = { bytes: otherBytes, mimeType: 'audio/mpeg', delay: 100 };
    provider.resetMaxActive();
    const offsets = Array.from({ length: 12 }, (_, i) => (i * 917123) % otherBytes.length);
    await Promise.all(offsets.map(async (offset) => {
      const response = await fetchRange(makeUrl('parallel', otherBytes.length, 'audio/mpeg'), `bytes=${offset}-`);
      await expectRange(response, otherBytes, offset, Math.min(otherBytes.length, offset + PART_LENGTH));
    }));
    assert(provider.maxActive <= MAX_CONCURRENT_LOADS, `${provider.maxActive} parts loaded at once`);
    return `12 requests, at most ${provider.maxActive} parts loading at once`;
  });
  await runCheck('contentTypeGuard', async () => {
    provider.files.page = { bytes: makeBytes(1000, 3), mimeType: 'text/html', delay: 0 };
    const response = await fetchRange('./progressive/page?mimeType=text%2Fhtml', 'bytes=0-');
    expectHeader(response, 'content-type', 'application/octet-stream');
    expectHeader(response, 'content-security-policy', 'sandbox');
    return 'text/html is served as application/octet-stream in a sandbox';
  });
  await runCheck('failedPart', async () => {
    provider.files.broken = { bytes: makeBytes(1000, 4), mimeType: 'video/mp4', isBroken: true };
    let error;
    try {
      await fetchRange('./progressive/broken', 'bytes=0-');
    } catch (err) {
      error = err;
    }
    assert(error, 'a part the page could not download did not fail the request');
    await expectRange(await fetchRange(url, 'bytes=10-20'), bytes, 10, 21);
    return `the request failed (${describeError(error)}), the next one worked`;
  });
  await runCheck('abortedFetch', async () => {
    const controller = new AbortController();
    const response = await fetch(url, { signal: controller.signal, cache: 'no-store' });
    const reader = response.body.getReader();
    await reader.read();
    controller.abort();
    await expectRange(await fetchRange(url, 'bytes=700000-700100'), bytes, 700000, 700101);
    return 'a request stopped while streaming leaves the stream working';
  });
}

async function runMediaChecks() {
  await runCheck('audioStreamsAndSeeks', async () => {
    const wav = makeWav(AUDIO_SECONDS, AUDIO_SAMPLE_RATE);
    provider.files.music = { bytes: wav, mimeType: 'audio/wav', delay: AUDIO_PART_DELAY_MS };
    const seekTo = AUDIO_SECONDS * AUDIO_SEEK_FRACTION;
    const result = await playMedia('audio', makeUrl('music', wav.length, 'audio/wav'), { seekTo, provider, name: 'music' });
    const totalParts = countParts(wav.length);
    const seekPart = Math.floor((44 + Math.floor(seekTo * AUDIO_SAMPLE_RATE) * 2) / PART_LENGTH);
    info.audio = { ...result, totalParts, seekPart };
    assert(result.partsBeforePlaying < totalParts,
      `playback waited for all ${totalParts} parts`);
    assert(result.requestedParts.includes(seekPart), `the seek did not ask for part ${seekPart}`);
    return `played ${describePlayback(result)}; ${result.partsBeforePlaying} of ${totalParts} parts were in when it `
      + `started`;
  });

  await runCheck('videoPlaysAndSeeks', async () => {
    provider.files.video = { bytes: paddedVideo, mimeType: 'video/mp4', delay: VIDEO_PART_DELAY_MS };
    const result = await playMedia('video', makeUrl('video', paddedVideo.length, 'video/mp4'), {
      seekTo: 2, provider, name: 'video',
    });
    info.video = result;
    return `played ${describePlayback(result)}; parts ${result.requestedParts.join(', ')} of `
      + `${countParts(paddedVideo.length)} were asked for`;
  });
}

// Plays a media element until it plays, seeks to `seekTo` and plays past it. With a provider, it also records which
// parts the stream asked for before playback started.
function playMedia(tagName, src, { seekTo, provider: recordingProvider, name } = {}) {
  return new Promise((resolve, reject) => {
    const element = document.createElement(tagName);
    element.muted = true;
    element.playsInline = true;
    element.preload = 'auto';
    if (tagName === 'video') {
      element.style.cssText = 'position: fixed; left: 0; bottom: 0; width: 64px; height: 64px; z-index: 9999;';
      document.body.appendChild(element);
    }
    const startedAt = performance.now();
    const result = {};
    let timeout;
    const cleanUp = () => {
      clearTimeout(timeout);
      element.pause();
      element.removeAttribute('src');
      element.load();
      element.remove();
    };
    const fail = (message) => {
      cleanUp();
      reject(new Error(`${message} (readyState ${element.readyState}, networkState ${element.networkState}, `
        + `error ${element.error && element.error.code})`));
    };

    element.addEventListener('error', () => fail('the media element failed'));
    element.addEventListener('playing', () => {
      if (result.playingMs !== undefined) return;
      result.playingMs = Math.round(performance.now() - startedAt);
      if (recordingProvider) result.partsBeforePlaying = recordingProvider.countServedParts(name);
      result.duration = Number(element.duration.toFixed(2));
      element.currentTime = seekTo;
      result.seekStartedAt = performance.now();
    });
    element.addEventListener('seeked', () => {
      if (result.seekedMs !== undefined || result.seekStartedAt === undefined) return;
      result.seekedMs = Math.round(performance.now() - result.seekStartedAt);
    });
    element.addEventListener('timeupdate', () => {
      if (result.seekedMs === undefined || element.currentTime < seekTo + 0.2) return;
      result.playedTo = Number(element.currentTime.toFixed(2));
      delete result.seekStartedAt;
      if (recordingProvider) result.requestedParts = recordingProvider.listRequestedParts(name);
      cleanUp();
      resolve(result);
    });

    element.src = src;
    element.play().catch((err) => fail(`play() failed: ${describeError(err)}`));
    timeout = setTimeout(() => fail(`no playback past ${seekTo} s: ${JSON.stringify(result)}`), CHECK_TIMEOUT_MS - 1000);
  });
}

// A synthetic `loadMediaPart` that serves test files with a delay and records the parts the stream asked for
function makeProvider() {
  const files = {};
  const requests = [];
  let active = 0;
  let maxActive = 0;

  return {
    files,
    get maxActive() {
      return maxActive;
    },
    resetMaxActive() {
      maxActive = 0;
    },
    countServedParts(name) {
      return new Set(requests.filter((request) => request.name === name && request.isServed)
        .map((request) => request.part)).size;
    },
    listRequestedParts(name) {
      return Array.from(new Set(requests.filter((request) => request.name === name).map((request) => request.part)))
        .sort((a, b) => a - b);
    },
    async load(url, start, end) {
      const match = String(url).match(/\/progressive\/([\w-]+)/);
      const name = match && match[1];
      const file = files[name];
      const request = { name, part: Math.floor(start / PART_LENGTH), isServed: false };
      requests.push(request);
      if (!file || file.isBroken) return undefined;

      active++;
      maxActive = Math.max(maxActive, active);
      try {
        await pause(file.delay || 0);
        const bytes = file.bytes.subarray(start, Math.min(end + 1, file.bytes.length));
        request.isServed = true;
        return { data: encodeBase64(bytes), mimeType: file.mimeType, fullSize: file.bytes.length };
      } finally {
        active--;
      }
    },
  };
}

// Inserts a `free` box of `padding` bytes after `moov` and moves the chunk offsets along, so the media data of a
// faststart MP4 starts `padding` bytes later
function padMp4(bytes, padding) {
  const moov = findBoxes(bytes, 0, bytes.length).find((box) => box.type === 'moov');
  assert(moov, 'nojs.mp4 has no moov box');
  const insertAt = moov.start + moov.size;
  const result = new Uint8Array(bytes.length + padding);
  result.set(bytes.subarray(0, insertAt), 0);
  result.set(bytes.subarray(insertAt), insertAt + padding);
  const view = new DataView(result.buffer);
  view.setUint32(insertAt, padding);
  writeAscii(result, insertAt + 4, 'free');
  moveChunkOffsets(result, moov.start, moov.size, padding);
  return result;
}

function moveChunkOffsets(bytes, start, size, delta) {
  const view = new DataView(bytes.buffer);
  const containers = ['moov', 'trak', 'mdia', 'minf', 'stbl'];
  findBoxes(bytes, start + 8, start + size).forEach((box) => {
    if (containers.includes(box.type)) {
      moveChunkOffsets(bytes, box.start, box.size, delta);
    } else if (box.type === 'stco') {
      const count = view.getUint32(box.start + 12);
      for (let i = 0; i < count; i++) {
        const offset = box.start + 16 + 4 * i;
        view.setUint32(offset, view.getUint32(offset) + delta);
      }
    } else if (box.type === 'co64') {
      const count = view.getUint32(box.start + 12);
      for (let i = 0; i < count; i++) {
        const offset = box.start + 16 + 8 * i;
        view.setBigUint64(offset, view.getBigUint64(offset) + BigInt(delta));
      }
    }
  });
}

function findBoxes(bytes, start, end) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const boxes = [];
  let offset = start;
  while (offset + 8 <= end) {
    const size = view.getUint32(offset);
    const type = String.fromCharCode(...bytes.subarray(offset + 4, offset + 8));
    if (size < 8) break;
    boxes.push({ type, start: offset, size });
    offset += size;
  }
  return boxes;
}

// A mono 16-bit PCM WAV file with a 440 Hz tone
function makeWav(seconds, sampleRate) {
  const sampleCount = seconds * sampleRate;
  const bytes = new Uint8Array(44 + sampleCount * 2);
  const view = new DataView(bytes.buffer);
  writeAscii(bytes, 0, 'RIFF');
  view.setUint32(4, 36 + sampleCount * 2, true);
  writeAscii(bytes, 8, 'WAVE');
  writeAscii(bytes, 12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeAscii(bytes, 36, 'data');
  view.setUint32(40, sampleCount * 2, true);
  for (let i = 0; i < sampleCount; i++) {
    view.setInt16(44 + i * 2, Math.round(Math.sin((2 * Math.PI * 440 * i) / sampleRate) * 8000), true);
  }
  return bytes;
}

function makeBytes(length, seed) {
  const bytes = new Uint8Array(length);
  let state = seed;
  for (let i = 0; i < length; i++) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    bytes[i] = state >>> 24;
  }
  return bytes;
}

function makeUrl(hash, length, mimeType) {
  return `./progressive/${hash}?fileSize=${length}&mimeType=${encodeURIComponent(mimeType)}`;
}

function fetchRange(url, range) {
  return fetch(url, { headers: { Range: range }, cache: 'no-store' });
}

async function expectRange(response, bytes, start, end) {
  assert(response.status === 206, `status ${response.status} for ${start}-${end - 1}`);
  expectHeader(response, 'content-range', `bytes ${start}-${end - 1}/${bytes.length}`);
  expectHeader(response, 'content-length', String(end - start));
  expectBytes(new Uint8Array(await response.arrayBuffer()), bytes, start, end);
}

function expectHeader(response, name, expected) {
  const value = response.headers.get(name);
  assert(value === expected, `${name} is ${value}, expected ${expected}`);
}

function expectBytes(received, bytes, start, end) {
  assert(received.length === end - start, `received ${received.length} bytes instead of ${end - start}`);
  for (let i = 0; i < received.length; i++) {
    if (received[i] !== bytes[start + i]) throw new Error(`byte ${start + i} differs`);
  }
}

function countParts(length) {
  return Math.ceil(length / PART_LENGTH);
}

function describePlayback(result) {
  return `in ${result.playingMs} ms, seeked in ${result.seekedMs} ms and played to ${result.playedTo} s of `
    + `${result.duration} s`;
}

function writeAscii(bytes, offset, text) {
  for (let i = 0; i < text.length; i++) {
    bytes[offset + i] = text.charCodeAt(i);
  }
}

function encodeBase64(bytes) {
  if (typeof bytes.toBase64 === 'function') return bytes.toBase64();

  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode.apply(undefined, bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function pause(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function runCheck(name, check) {
  try {
    const detail = await withTimeout(Promise.resolve().then(check));
    checks.push({ name, ok: true, detail: String(detail) });
  } catch (err) {
    checks.push({ name, ok: false, detail: describeError(err) });
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

function describeError(err) {
  if (err instanceof Error) return `${err.name}: ${err.message}`;
  return String(err);
}
