const APP_URL = chrome.runtime.getURL('index.html');
const TEXT_TAB_FAILED = 'Не получилось открыть вкладку. Попробуй ещё раз.';
const TEXT_SIDE_PANEL_FAILED = 'Не получилось открыть боковую панель. Открой Liquidgram во вкладке.';

const openTabButton = document.getElementById('open-tab');
const openSideButton = document.getElementById('open-side');
const statusElement = document.getElementById('status');

let currentWindowId;
const isCurrentWindowKnownPromise = chrome.windows.getCurrent().then((currentWindow) => {
  currentWindowId = currentWindow.id;
  return true;
}, () => false);

openTabButton.addEventListener('click', handleOpenTabClick);

if (chrome.sidePanel?.open) {
  // `sidePanel.open` must run synchronously inside the click to keep the user gesture, so it waits for the window ID
  openSideButton.disabled = true;
  isCurrentWindowKnownPromise.then((isKnown) => {
    if (isKnown) {
      openSideButton.disabled = false;
    } else {
      showStatus(TEXT_SIDE_PANEL_FAILED);
    }
  });
  openSideButton.addEventListener('click', handleOpenSideClick);
} else {
  openSideButton.hidden = true;
}

// Reuses an already open Liquidgram tab instead of starting a second client
async function handleOpenTabClick() {
  openTabButton.disabled = true;

  try {
    const appContext = await findAppContext();
    if (appContext) {
      await chrome.tabs.update(appContext.tabId, { active: true });
      await chrome.windows.update(appContext.windowId, { focused: true });
    } else {
      await chrome.tabs.create({ url: APP_URL });
    }

    window.close();
  } catch {
    openTabButton.disabled = false;
    showStatus(TEXT_TAB_FAILED);
  }
}

function handleOpenSideClick() {
  try {
    chrome.sidePanel.open({ windowId: currentWindowId })
      .then(() => window.close(), () => showStatus(TEXT_SIDE_PANEL_FAILED));
  } catch {
    showStatus(TEXT_SIDE_PANEL_FAILED);
  }
}

// `runtime.getContexts` lists the extension's own tabs without the `tabs` permission
async function findAppContext() {
  if (!chrome.runtime.getContexts) return undefined;

  const contexts = await chrome.runtime.getContexts({ contextTypes: ['TAB'] });
  const appContexts = contexts.filter((context) => context.documentUrl?.startsWith(APP_URL));

  return appContexts.find((context) => context.windowId === currentWindowId) || appContexts[0];
}

function showStatus(text) {
  statusElement.textContent = text;
  statusElement.hidden = false;
}
