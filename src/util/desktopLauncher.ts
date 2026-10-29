import { MouseButton } from './browser/windowEnvironment';

// The desktop launcher in `desktop/launcher` serves the app on this host and answers these paths
const LAUNCHER_HOSTNAME = '127.0.0.1';
const LAUNCHER_PING_URL = './__liquidgram/ping';
const LAUNCHER_OPEN_URL = './__liquidgram/open-url';
const LAUNCHER_INSTANCE_HEADER = 'X-Liquidgram-Instance';
const LAUNCHER_SIGNATURE = 'liquidgram';
const RE_WEB_PROTOCOL = /^https?:$/;

type LauncherPing = {
  app?: string;
  instance?: string;
};

let isSetup = false;
let launcherInstanceId: string | undefined;
let openBrowserWindow: typeof window.open;

// The launcher shows the app in a browser window with a profile of its own, so links to other sites go to
// the default browser, where the user's sign-ins and bookmarks live
export default async function setupDesktopLauncherLinks() {
  if (isSetup || window.location.hostname !== LAUNCHER_HOSTNAME) return;
  isSetup = true;

  launcherInstanceId = await fetchLauncherInstanceId();
  if (!launcherInstanceId) return;

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
  if (e.defaultPrevented) return;

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
      headers: { [LAUNCHER_INSTANCE_HEADER]: launcherInstanceId! },
    });
    if (response.ok) return;
  } catch {
    // Falls back to a window of the app profile below
  }

  openBrowserWindow(url, target, features);
}

async function fetchLauncherInstanceId() {
  try {
    const response = await fetch(LAUNCHER_PING_URL, { cache: 'no-store' });
    const ping: LauncherPing = await response.json();
    return ping.app === LAUNCHER_SIGNATURE ? ping.instance : undefined;
  } catch {
    return undefined;
  }
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
