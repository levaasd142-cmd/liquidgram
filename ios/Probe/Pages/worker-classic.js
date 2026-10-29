// A classic dedicated worker: `importScripts()`, fetch, Web Crypto, WebSocket and BroadcastChannel from a worker
let importedHelper;
try {
  importScripts('helper-import.js', 'worker-common.js');
  importedHelper = self.__probeHelper;
} catch (err) {
  importedHelper = `importScripts failed: ${err.message}`;
}

self.onmessage = async (event) => {
  const { task, url } = event.data || {};
  const checks = self.__probeWorkerChecks;
  if (!checks) {
    self.postMessage({ result: { importScripts: importedHelper }, errors: ['worker-common.js did not load'] });
    return;
  }

  if (task === 'broadcast') {
    const channel = new BroadcastChannel('probe-worker-channel');
    channel.postMessage('from-worker');
    // Lets the message leave the worker before the page terminates it
    setTimeout(() => {
      channel.close();
      self.postMessage({ result: { broadcast: 'sent' }, errors: [] });
    }, 300);
    return;
  }

  const named = {
    fetch: () => checks.fetchData(),
    subtle: () => checks.digest(),
  };
  if (task === 'websocket') {
    named.websocket = () => checks.openAndCloseWebSocket(url);
  }
  const { result, errors } = await checks.run(named);
  result.importScripts = importedHelper;
  result.origin = self.origin;
  result.isSecureContext = self.isSecureContext;
  if (importedHelper !== 'helper-ok') errors.push(`importScripts: ${importedHelper}`);
  if (!self.isSecureContext) errors.push('not a secure context');
  self.postMessage({ result, errors });
};
