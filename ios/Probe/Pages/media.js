// Repeats media playback with seeking over one origin, so a rare stall shows up as a rate instead of a single
// failure. Each attempt uses a new element and a new URL, so no attempt reuses the data of another.
import { createVideo, playAndSeek } from './media-common.js';

const REPEATS = 4;
const SEEK_FRACTION = 0.6;
const VARIANTS = [
  { name: 'video-seek-repeat', src: '/__probe/probe-video.mp4', isVideo: true },
  { name: 'video-faststart-seek-repeat', src: '/__probe/probe-video-faststart.mp4', isVideo: true },
  { name: 'video-paused-seek-repeat', src: '/__probe/probe-video.mp4', isVideo: true, isPausedSeek: true },
  { name: 'audio-seek-repeat', src: '/__probe/probe-audio.m4a', isVideo: false },
];

const post = window.__probePost || ((message) => console.log('[probe]', JSON.stringify(message)));
const list = document.getElementById('list');
const stage = document.getElementById('stage');

void main();

async function main() {
  document.getElementById('title').textContent = `Media probe: ${window.location.origin}`;
  for (const variant of VARIANTS) {
    const attempts = [];
    let failures = 0;
    for (let attempt = 1; attempt <= REPEATS; attempt++) {
      const media = variant.isVideo ? createVideo(stage) : new Audio();
      const src = `${variant.src}?attempt=${attempt}`;
      try {
        const result = await playAndSeek(media, src, stage, {
          seekFraction: SEEK_FRACTION, isPausedSeek: variant.isPausedSeek,
        });
        attempts.push(`#${attempt} seeked in ${result.seekMs} ms`);
      } catch (err) {
        failures += 1;
        attempts.push(`#${attempt} FAILED ${err.message}`);
      }
      media.remove();
    }
    report(variant.name, failures === 0, `${REPEATS - failures}/${REPEATS}: ${attempts.join('; ')}`);
  }
  post({ type: 'done' });
}

function report(name, ok, detail) {
  post({
    type: 'check', name, ok, detail: detail.slice(0, 4000),
  });
  const item = document.createElement('li');
  item.className = ok ? 'ok' : 'fail';
  item.textContent = `${ok ? 'PASS' : 'FAIL'} ${name}: ${detail.slice(0, 200)}`;
  list.appendChild(item);
}
