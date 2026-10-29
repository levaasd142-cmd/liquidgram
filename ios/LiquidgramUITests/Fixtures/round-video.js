// Body of the async function that `TestHooks` runs in the page through `LIQUIDGRAM_TEST_SELFTEST_SCRIPT` for
// `RoundVideoTests`. It opens the app's round video recorder through the bridge, as the composer does, while the test
// drives the recorder on screen, and returns a JSON report of what the page got. Once the recorder answers with a
// recording, the page fetches it the way the web app does: whole into a Blob, which a video element must decode, then
// a byte range, then once more after `releaseMedia`. Those requests reach the recording only when `AppSchemeHandler`
// serves the page; the test checks them then.
'use strict';

const SECOND_REQUEST_TIMEOUT_MS = 2000;
const RELEASE_WAIT_MS = 500;
const DECODE_TIMEOUT_MS = 10000;
const RANGE_END = 1;
const MAX_REPORTED_ERRORS = 5;

const native = window.__liquidgramNative;
const report = {
  origin: location.origin,
  hasRecorder: Boolean(native) && typeof native.recordRoundVideo === 'function',
};
if (!report.hasRecorder) return JSON.stringify(report);

const recording = native.recordRoundVideo({ canSendOneTimeMedia: true });
// While the recorder is up, another request gets `null` at once
report.secondRequest = await Promise.race([
  native.recordRoundVideo({}),
  wait(SECOND_REQUEST_TIMEOUT_MS).then(() => 'pending'),
]);
const result = await recording;
report.result = result;
if (result) {
  report.fetch = await describeFetch(result.url);
  report.range = await describeRange(result.url);
  native.releaseMedia(result.url);
  await wait(RELEASE_WAIT_MS);
  report.afterRelease = await describeStatus(result.url);
}
report.pageErrors = (window.__liquidgramTestErrors || []).slice(0, MAX_REPORTED_ERRORS);
return JSON.stringify(report);

async function describeFetch(url) {
  try {
    const response = await fetch(url, { cache: 'no-store' });
    const blob = await response.blob();
    const description = {
      status: response.status,
      contentType: response.headers.get('content-type'),
      blobType: blob.type,
      size: blob.size,
    };
    if (response.ok) {
      description.topLevelBoxes = readTopLevelBoxes(new Uint8Array(await blob.arrayBuffer()));
      description.video = await describeVideo(blob);
    }
    return description;
  } catch (err) {
    return { error: describeError(err) };
  }
}

async function describeRange(url) {
  try {
    const response = await fetch(url, { cache: 'no-store', headers: { Range: `bytes=0-${RANGE_END}` } });
    const bytes = new Uint8Array(await response.arrayBuffer());
    return {
      status: response.status,
      contentRange: response.headers.get('content-range'),
      length: bytes.length,
    };
  } catch (err) {
    return { error: describeError(err) };
  }
}

async function describeStatus(url) {
  try {
    const response = await fetch(url, { cache: 'no-store' });
    return { status: response.status };
  } catch (err) {
    return { error: describeError(err) };
  }
}

// The web app makes the poster of a round video from a video element that plays the Blob
function describeVideo(blob) {
  const objectUrl = URL.createObjectURL(blob);
  const video = document.createElement('video');
  video.muted = true;
  video.playsInline = true;
  return new Promise((resolve) => {
    const timeout = setTimeout(() => finish({ error: `no metadata in ${DECODE_TIMEOUT_MS} ms` }), DECODE_TIMEOUT_MS);
    video.onloadedmetadata = () => finish({
      width: video.videoWidth,
      height: video.videoHeight,
      durationMs: Math.round(video.duration * 1000),
    });
    video.onerror = () => finish({ error: `media error ${video.error && video.error.code}` });
    video.src = objectUrl;

    function finish(value) {
      clearTimeout(timeout);
      video.removeAttribute('src');
      URL.revokeObjectURL(objectUrl);
      resolve(value);
    }
  });
}

function readTopLevelBoxes(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const types = [];
  let offset = 0;
  while (offset + 8 <= bytes.length) {
    const size = view.getUint32(offset);
    types.push(String.fromCharCode(...bytes.subarray(offset + 4, offset + 8)));
    if (size < 8) break;
    offset += size;
  }
  return types;
}

function wait(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function describeError(err) {
  return err instanceof Error ? `${err.name}: ${err.message}` : String(err);
}
