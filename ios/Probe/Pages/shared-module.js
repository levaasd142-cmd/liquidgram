// A module shared worker with a static import, like `sharedState.worker` of the web app, plus fetch and Web Crypto
import { depValue } from './module-dep.js';
import './worker-common.js';

self.onconnect = (event) => {
  const port = event.ports[0];
  port.onmessage = async () => {
    const checks = self.__probeWorkerChecks;
    const { result, errors } = await checks.run({
      fetch: () => checks.fetchData(),
      subtle: () => checks.digest(),
    });
    result.staticImport = depValue;
    result.origin = self.origin;
    result.isSecureContext = self.isSecureContext;
    port.postMessage({ result, errors });
  };
};
