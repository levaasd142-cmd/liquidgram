import type { LiquidSettings } from '../global/types';

import { SVG_NAMESPACE } from '../config';
import { IS_BACKDROP_BLUR_SUPPORTED, IS_CHROMIUM, IS_IOS } from './browser/windowEnvironment';
import { addSvgDefinition } from './svgController';

// Only Chromium renders SVG filters referenced from `backdrop-filter`
export const IS_GLASS_REFRACTION_SUPPORTED = IS_CHROMIUM && !IS_IOS && IS_BACKDROP_BLUR_SUPPORTED;

const NEUTRAL_DISPLACEMENT_COLOR = 'rgb(128,128,0)';
const BEZEL_BLUR_RATIO = 2.5;

// Displacement maps are stretched over the element, so each shape uses a map with typical proportions
const REFRACTION_SHAPES = [
  {
    id: 'lg-refract-pill', width: 672, height: 48, bezel: 11, scale: -26,
  },
  {
    id: 'lg-refract-round', width: 48, height: 48, bezel: 13, scale: -30,
  },
  {
    id: 'lg-refract-panel', width: 360, height: 860, bezel: 18, scale: -36,
  },
];

let areRefractionFiltersAdded = false;

export function applyLiquidSettings(settings: LiquidSettings) {
  const root = document.documentElement;
  const isRefractionEnabled = settings.isGlassEnabled && settings.isRefractionEnabled
    && IS_GLASS_REFRACTION_SUPPORTED;

  if (isRefractionEnabled && !areRefractionFiltersAdded) {
    addRefractionFilters();
  }

  root.classList.toggle('liquid-glass', settings.isGlassEnabled);
  root.classList.toggle('liquid-refraction', isRefractionEnabled);
  root.classList.toggle('liquid-streamer', settings.isStreamerModeEnabled);
  root.style.setProperty('--lg-intensity', String(settings.glassIntensity / 100));
}

function addRefractionFilters() {
  areRefractionFiltersAdded = true;

  REFRACTION_SHAPES.forEach(({
    id, width, height, bezel, scale,
  }) => {
    addSvgDefinition((
      <filter x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB" xmlns={SVG_NAMESPACE}>
        <feImage
          href={buildDisplacementMap(width, height, bezel)}
          x="0"
          y="0"
          width="100%"
          height="100%"
          preserveAspectRatio="none"
          result="map"
        />
        <feDisplacementMap in="SourceGraphic" in2="map" scale={scale} xChannelSelector="R" yChannelSelector="G" />
      </filter>
    ), id);
  });
}

// Red and green ramps shift pixels near the edges, while the blurred neutral core keeps the center undistorted
function buildDisplacementMap(width: number, height: number, bezel: number) {
  const radius = Math.max(0, Math.min(width, height) / 2 - bezel);
  const svg = `<svg xmlns="${SVG_NAMESPACE}" width="${width}" height="${height}">`
    + '<defs>'
    + '<linearGradient id="x" x2="1" y2="0"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#f00"/>'
    + '</linearGradient>'
    + '<linearGradient id="y" x2="0" y2="1"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#0f0"/>'
    + '</linearGradient>'
    + `<filter id="b"><feGaussianBlur stdDeviation="${bezel / BEZEL_BLUR_RATIO}"/></filter>`
    + '</defs>'
    + `<rect width="${width}" height="${height}" fill="url(#x)"/>`
    + `<rect width="${width}" height="${height}" fill="url(#y)" style="mix-blend-mode:screen"/>`
    + `<rect x="${bezel}" y="${bezel}" width="${width - bezel * 2}" height="${height - bezel * 2}" rx="${radius}"`
    + ` fill="${NEUTRAL_DISPLACEMENT_COLOR}" filter="url(#b)"/>`
    + '</svg>';

  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}
