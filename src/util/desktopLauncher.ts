import { MouseButton } from './browser/windowEnvironment';
import { getLauncherToken } from './desktopLauncherToken';

const LAUNCHER_OPEN_URL = './__liquidgram/open-url';
const LAUNCHER_TOKEN_HEADER = 'X-Liquidgram-Token';
const RE_WEB_PROTOCOL = /^https?:$/;

let isSetup = false;
let openBrowserWindow: typeof window.open;

// The desktop launcher shows the app in a browser window with a profile of its own, so links to other sites
// go to the default browser, where the user's sign-ins and bookmarks live
export default function setupDesktopLauncherLinks() {
  if (isSetup || !getLauncherToken()) return;
  isSetup = true;

  openBrowserWindow = window.open.bind(window);
  window.open = openWindowOrExternalUrl;

  // Run after Teact's delegated handlers so links can require confirmation
  window.addEventListener('click', handleLinkClick);
  window.addEventListener('auxclick', handleLinkClick);
}

function openWindowOrExternalUrl(url?: string | URL, target?: string, features?: string) {
  const externalUrl = url !== undefined ? getExternalUrl(url) : undefined;
  if (!externalUrl) return openBrowserWindow(url, target, features);

  openInDefaultBrowser(externalUrl, target, features);
  // eslint-disable-next-line no-null/no-null
  return null;
}

function handleLinkClick(e: MouseEvent) {
  // `auxclick` also fires for the right button, which opens the context menu
  const isOpeningButton = e.button === MouseButton.Main || e.button === MouseButton.Auxiliary;
  if (e.defaultPrevented || !isOpeningButton) return;

  const anchor = (e.target as HTMLElement | null)?.closest<HTMLAnchorElement>('a[href]');
  if (!anchor) return;

  const isNewWindowClick = anchor.target === '_blank' || e.ctrlKey || e.metaKey || e.shiftKey
    || e.button === MouseButton.Auxiliary;
  const externalUrl = isNewWindowClick ? getExternalUrl(anchor.href) : undefined;
  if (!externalUrl) return;

  e.preventDefault();
  openInDefaultBrowser(externalUrl, '_blank', 'noopener');
}

async function openInDefaultBrowser(url: string, target?: string, features?: string) {
  try {
    const response = await fetch(`${LAUNCHER_OPEN_URL}?url=${encodeURIComponent(url)}`, {
      headers: { [LAUNCHER_TOKEN_HEADER]: getLauncherToken()! },
    });
    if (response.ok) return;
  } catch {
    // Falls back to a window of the app profile below
  }

  openBrowserWindow(url, target, features);
}

function getExternalUrl(url: string | URL) {
  try {
    const parsedUrl = new URL(url, window.location.href);
    const isExternal = RE_WEB_PROTOCOL.test(parsedUrl.protocol) && parsedUrl.origin !== window.location.origin;
    return isExternal ? parsedUrl.href : undefined;
  } catch {
    return undefined;
  }
}
