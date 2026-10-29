// Gives the YouTube player time to render, then ends the page for the snapshot
const RENDER_DELAY_MS = 10000;

setTimeout(() => {
  if (window.__probePost) {
    window.__probePost({ type: 'done' });
  }
}, RENDER_DELAY_MS);
