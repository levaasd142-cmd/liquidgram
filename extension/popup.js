const APP_URL = chrome.runtime.getURL('index.html');

const openTabButton = document.getElementById('open-tab');
const openSideButton = document.getElementById('open-side');

let currentWindowId;
chrome.windows.getCurrent().then((currentWindow) => {
  currentWindowId = currentWindow.id;
});

// Reuses an already open Liquidgram tab instead of starting a second client
openTabButton.addEventListener('click', async () => {
  const contexts = chrome.runtime.getContexts
    ? await chrome.runtime.getContexts({ contextTypes: ['TAB'] })
    : [];
  const appContext = contexts.find((context) => context.documentUrl?.startsWith(APP_URL));

  if (appContext) {
    await chrome.tabs.update(appContext.tabId, { active: true });
    await chrome.windows.update(appContext.windowId, { focused: true });
  } else {
    await chrome.tabs.create({ url: APP_URL });
  }

  window.close();
});

if (chrome.sidePanel?.open) {
  // `sidePanel.open` must run synchronously inside the click to keep the user gesture
  openSideButton.addEventListener('click', () => {
    chrome.sidePanel.open({ windowId: currentWindowId }).then(() => window.close());
  });
} else {
  openSideButton.hidden = true;
}
