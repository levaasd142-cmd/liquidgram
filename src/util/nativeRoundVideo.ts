// Round video messages in the iPhone app. WebKit cannot record them in the page (see `IS_VIDEO_RECORDING_SUPPORTED`),
// so the app records them with the camera and serves the MP4 to the page once, see
// `ios/Liquidgram/Resources/bridge.js`.

import { pause as pauseAudioPlayback } from './audioPlayback/playbackController';

// The app's answer: a square H.264 and AAC MP4 that it serves at `url`, a path under `/__liquidgram/media/`, until the
// page releases it
export type NativeRoundVideoFile = {
  url: string;
  durationMs: number;
  width: number;
  height: number;
  isViewOnce: boolean;
};

export type NativeRoundVideo = {
  blob: Blob;
  // Whole seconds, as round video attachments take them
  duration: number;
  durationMs: number;
  width: number;
  height: number;
  isViewOnce: boolean;
};

const MIME_TYPE = 'video/mp4';
const MS_IN_SECOND = 1000;

// Shows the app's camera screen. Resolves with the recorded video, or with `undefined` when the user cancels.
export async function recordNativeRoundVideo(canSendOneTimeMedia: boolean): Promise<NativeRoundVideo | undefined> {
  const native = window.__liquidgramNative!;
  // The recording takes the audio session, which stops a playing message anyway
  pauseAudioPlayback();

  const file = await native.recordRoundVideo!({ canSendOneTimeMedia });
  if (!file) return undefined;

  try {
    const response = await fetch(file.url, { cache: 'no-store' });
    if (!response.ok) {
      throw new Error(`The app did not serve the round video: ${response.status}`);
    }

    const blob = await response.blob();
    return {
      // The upload takes its MIME type from the blob
      blob: blob.type === MIME_TYPE ? blob : blob.slice(0, blob.size, MIME_TYPE),
      duration: Math.max(1, Math.round(file.durationMs / MS_IN_SECOND)),
      durationMs: file.durationMs,
      width: file.width,
      height: file.height,
      isViewOnce: file.isViewOnce,
    };
  } finally {
    native.releaseMedia!(file.url);
  }
}
