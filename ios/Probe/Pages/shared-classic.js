// A classic shared worker: `importScripts()`, fetch and Web Crypto. WebKit runs shared workers outside the page, so
// their own loads may take another path than the page's.
let importedHelper;
try {
  importScripts('helper-import.js', 'worker-common.js');
  importedHelper = self.__probeHelper;
} catch (err) {
  importedHelper = `importScripts failed: ${err.message}`;
}

self.onconnect = (event) => {
  const port = event.ports[0];
  port.onmessage = async () => {
    const checks = self.__probeWorkerChecks;
    if (!checks) {
      port.postMessage({ result: { importScripts: importedHelper }, errors: ['worker-common.js did not load'] });
      return;
    }
    const { result, errors } = await checks.run({
      fetch: () => checks.fetchData(),
      subtle: () => checks.digest(),
    });
    result.importScripts = importedHelper;
    result.origin = self.origin;
    result.isSecureContext = self.isSecureContext;
    if (importedHelper !== 'helper-ok') errors.push(`importScripts: ${importedHelper}`);
    port.postMessage({ result, errors });
  };
};
