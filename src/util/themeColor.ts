// The `theme-color` meta tints the browser interface around the page and, in the iOS app, the strip under the status
// bar. Overlays that cover the whole page put their own color over the theme's while they are open.
const metaThemeColor = document.querySelector('meta[name="theme-color"]');
const overlays: { color: string }[] = [];

let themeColor = metaThemeColor?.getAttribute('content') || undefined;

export function setThemeColor(color: string) {
  themeColor = color;
  applyThemeColor();
}

export function addThemeColorOverlay(color: string) {
  const overlay = { color };
  overlays.push(overlay);
  applyThemeColor();

  return () => {
    overlays.splice(overlays.indexOf(overlay), 1);
    applyThemeColor();
  };
}

function applyThemeColor() {
  const color = overlays.length ? overlays[overlays.length - 1].color : themeColor;
  if (color) {
    metaThemeColor?.setAttribute('content', color);
  }
}
