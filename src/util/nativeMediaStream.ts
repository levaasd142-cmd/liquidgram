import { bufferToBase64 } from './encoding/buffer';

type MediaPartParams = {
  url: string;
  start: number;
  end: number;
};

type MediaPartResult = {
  arrayBuffer?: ArrayBuffer;
  mimeType?: string;
  fullSize?: number;
};

export type NativeMediaPart = {
  // The bytes in base64, the form in which they reach the app
  data: string;
  mimeType?: string;
  fullSize?: number;
};

// The iOS app has no service worker, so it answers the range requests of media elements for `./progressive/` URLs
// itself. For every part of a file it calls `window.__liquidgramNative.loadMediaPart`, which downloads the bytes
// through the API worker, as the service worker asks the page in browsers
export function registerNativeMediaPartLoader(
  loadPart: (params: MediaPartParams) => Promise<MediaPartResult | undefined>,
) {
  const native = window.__liquidgramNative;
  if (!native) return;

  native.loadMediaPart = async (url, start, end) => {
    const part = await loadPart({ url, start, end });
    if (!part?.arrayBuffer) return undefined;

    return {
      data: bufferToBase64(new Uint8Array(part.arrayBuffer)),
      mimeType: part.mimeType,
      fullSize: part.fullSize,
    };
  };
}
