const TYPE_HTML = 'text/html';
const CANONICAL_LINK_SELECTOR = 'link[rel~="canonical" i]';
const ALLOWED_EMBED_URL_PROTOCOLS = new Set(['http:', 'https:']);
const YOUTUBE_EMBED_HOSTS = new Set([
  'youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtube-nocookie.com', 'www.youtube-nocookie.com',
]);
const YOUTUBE_EMBED_PATH = /^\/embed\/([\w-]+)$/;
const YOUTUBE_WATCH_URL = 'https://www.youtube.com/watch';

export function extractInstantViewEmbedUrl(html: string) {
  try {
    const parser = new DOMParser();
    const parsedDocument = parser.parseFromString(html, TYPE_HTML);
    const canonicalLink = parsedDocument.querySelector<HTMLLinkElement>(CANONICAL_LINK_SELECTOR);
    const href = canonicalLink?.getAttribute('href')?.trim();

    return href ? normalizeEmbedUrl(href) : undefined;
  } catch (err) {
    return undefined;
  }
}

// The page of a YouTube player embed, which starts at the same second
export function getYoutubeWatchUrl(embedUrl: string) {
  try {
    const url = new URL(embedUrl);
    const videoId = YOUTUBE_EMBED_HOSTS.has(url.hostname) ? url.pathname.match(YOUTUBE_EMBED_PATH)?.[1] : undefined;
    if (!videoId) return undefined;

    const watchUrl = new URL(YOUTUBE_WATCH_URL);
    watchUrl.searchParams.set('v', videoId);
    const start = url.searchParams.get('start');
    if (start) watchUrl.searchParams.set('t', start);

    return watchUrl.href;
  } catch (err) {
    return undefined;
  }
}

function normalizeEmbedUrl(href: string) {
  try {
    const url = new URL(href);

    return ALLOWED_EMBED_URL_PROTOCOLS.has(url.protocol) ? url.href : undefined;
  } catch (err) {
    return undefined;
  }
}
