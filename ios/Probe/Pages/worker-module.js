// A module dedicated worker: static and dynamic imports, fetch, Web Crypto and streaming WebAssembly compilation
import { depValue } from './module-dep.js';
import './worker-common.js';

self.onmessage = async (event) => {
  const { wasmUrl } = event.data || {};
  const checks = self.__probeWorkerChecks;
  const named = {
    dynamicImport: async () => (await import('./module-dyn.js')).dynValue,
    fetch: () => checks.fetchData(),
    subtle: () => checks.digest(),
  };
  if (wasmUrl) {
    named.wasm = () => checks.compileWasm(wasmUrl);
  }
  const { result, errors } = await checks.run(named);
  result.staticImport = depValue;
  result.origin = self.origin;
  result.isSecureContext = self.isSecureContext;
  if (result.dynamicImport !== undefined && result.dynamicImport !== 'dyn-ok') errors.push('wrong dynamic import');
  if (!self.isSecureContext) errors.push('not a secure context');
  self.postMessage({ result, errors });
};
