// The desktop launcher in `desktop/launcher` serves the app on this host and one of these ports (`defaultPorts`
// in `ports.go`). It opens each window with its token in the URL fragment, which no server ever receives.
const LAUNCHER_HOSTNAME = '127.0.0.1';
const LAUNCHER_PORTS = new Set(['47819', '43819', '39819', '35819', '31819']);
const RE_LAUNCHER_TOKEN_HASH = /^#liquidgram-launcher=([0-9a-f]+)$/;
const LAUNCHER_TOKEN_STORAGE_KEY = 'lg-launcher-token';

let launcherToken: string | undefined;

// The routing calls this before it reads the URL, so the token never becomes part of a chat link. Windows opened
// later, reloads and other accounts of the same launch find the token in storage.
export function claimLauncherToken() {
  const { hostname, port } = window.location;
  if (hostname !== LAUNCHER_HOSTNAME || !LAUNCHER_PORTS.has(port)) return;

  launcherToken = takeTokenFromUrl() || readStoredToken();
}

export function getLauncherToken() {
  return launcherToken;
}

function takeTokenFromUrl() {
  const match = window.location.hash.match(RE_LAUNCHER_TOKEN_HASH);
  if (!match) return undefined;

  const { pathname, search } = window.location;
  window.history.replaceState(window.history.state, '', `${pathname}${search}`);
  try {
    localStorage.setItem(LAUNCHER_TOKEN_STORAGE_KEY, match[1]);
  } catch {
    // The token stays with this window only
  }
  return match[1];
}

function readStoredToken() {
  try {
    return localStorage.getItem(LAUNCHER_TOKEN_STORAGE_KEY) || undefined;
  } catch {
    return undefined;
  }
}
