// A classic shared worker without imports. WebKit fetches a shared worker's own script through the page that starts
// it, but runs the worker outside the page, so each load the worker makes itself is checked separately.
self.onconnect = (event) => {
  const port = event.ports[0];
  port.onmessage = async ({ data }) => {
    const answer = { origin: self.origin, isSecureContext: self.isSecureContext };
    try {
      switch (data && data.task) {
        case 'importScripts':
          importScripts('helper-import.js');
          answer.value = self.__probeHelper;
          break;
        case 'fetch': {
          const response = await fetch('data.json', { cache: 'no-store' });
          answer.value = `${response.status} ${(await response.json()).probe}`;
          break;
        }
        case 'subtle': {
          const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('abc'));
          answer.value = new Uint8Array(digest)[0] === 0xba ? 'SHA-256 ok' : 'wrong digest';
          break;
        }
        default:
          answer.value = 'pong';
      }
    } catch (err) {
      answer.error = `${err.name}: ${err.message}`;
    }
    port.postMessage(answer);
  };
};
