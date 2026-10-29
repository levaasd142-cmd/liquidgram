// Media helpers of the probe pages
const MEDIA_EVENT_TIMEOUT_MS = 15000;
const PLAYBACK_TIMEOUT_MS = 12000;
const MAX_SEEK_ERROR_SECONDS = 1.5;
const MIN_PROGRESS_SECONDS = 0.3;
const POLL_INTERVAL_MS = 100;
const LOGGED_EVENTS = ['loadedmetadata', 'canplay', 'playing', 'seeking', 'seeked', 'waiting', 'stalled'];

export function createVideo(stage) {
  const video = document.createElement('video');
  stage.appendChild(video);
  return video;
}

// Plays muted media from `src` and checks that playback progresses. With `seekFraction` it then seeks to that share
// of the duration, while playing or, with `isPausedSeek`, while paused, and checks that playback continues there,
// which needs range requests into the middle of the file. The event log goes to `stage`; the element is released at
// the end, which cancels its remaining loads.
export async function playAndSeek(media, src, stage, { seekFraction, isPausedSeek } = {}) {
  const events = [];
  LOGGED_EVENTS.forEach((name) => {
    media.addEventListener(name, () => events.push(`${name}@${media.currentTime.toFixed(1)}`));
  });
  media.muted = true;
  media.preload = 'auto';
  media.setAttribute('playsinline', '');
  const metadata = waitForMediaEvent(media, 'loadedmetadata');
  media.src = src;
  try {
    await metadata;
    if (!Number.isFinite(media.duration) || media.duration <= 0) throw new Error(`duration ${media.duration}`);
    if (!isPausedSeek) {
      await media.play();
      await waitForCondition(() => media.currentTime > MIN_PROGRESS_SECONDS, () => `playback (at ${media.currentTime})`);
    }
    const result = { duration: Number(media.duration.toFixed(2)) };
    if (seekFraction) {
      const target = media.duration * seekFraction;
      const seeked = waitForMediaEvent(media, 'seeked');
      const seekStartedAt = performance.now();
      media.currentTime = target;
      await seeked;
      result.seekMs = Math.round(performance.now() - seekStartedAt);
      if (Math.abs(media.currentTime - target) >= MAX_SEEK_ERROR_SECONDS) {
        throw new Error(`seeked to ${media.currentTime}, not ${target}`);
      }
      const seekedTo = media.currentTime;
      if (isPausedSeek) {
        await media.play();
      }
      await waitForCondition(
        () => media.currentTime > seekedTo + MIN_PROGRESS_SECONDS,
        () => `playback after the seek (at ${media.currentTime})`,
      );
      result.seekedTo = Number(seekedTo.toFixed(2));
      result.playedTo = Number(media.currentTime.toFixed(2));
    }
    if (media.videoWidth !== undefined) {
      result.size = `${media.videoWidth}x${media.videoHeight}`;
    }
    return result;
  } catch (err) {
    err.message = `${err.message}; events: ${events.join(' ')}`;
    throw err;
  } finally {
    media.pause();
    media.removeAttribute('src');
    media.load();
    const item = document.createElement('div');
    item.textContent = events.join(' ');
    stage.appendChild(item);
  }
}

function waitForMediaEvent(media, name) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`no ${name} (readyState ${media.readyState}, networkState ${media.networkState})`));
    }, MEDIA_EVENT_TIMEOUT_MS);
    function onEvent() {
      cleanup();
      resolve();
    }
    function onError() {
      cleanup();
      reject(new Error(`media error ${media.error ? `${media.error.code} ${media.error.message}` : 'unknown'}`));
    }
    function cleanup() {
      clearTimeout(timer);
      media.removeEventListener(name, onEvent);
      media.removeEventListener('error', onError);
    }
    media.addEventListener(name, onEvent);
    media.addEventListener('error', onError);
  });
}

function waitForCondition(condition, label) {
  return new Promise((resolve, reject) => {
    const startedAt = Date.now();
    (function poll() {
      if (condition()) {
        resolve();
        return;
      }
      if (Date.now() - startedAt > PLAYBACK_TIMEOUT_MS) {
        reject(new Error(`timeout waiting for ${label()}`));
        return;
      }
      setTimeout(poll, POLL_INTERVAL_MS);
    }());
  });
}
