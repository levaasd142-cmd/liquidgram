// A module shared worker with a static import, whose module graph the worker loads itself
import { depValue } from './module-dep.js';

self.onconnect = (event) => {
  const port = event.ports[0];
  port.onmessage = () => {
    port.postMessage({ origin: self.origin, isSecureContext: self.isSecureContext, value: depValue });
  };
};
