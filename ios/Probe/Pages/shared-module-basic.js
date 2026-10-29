// A module shared worker without imports, like `sharedState.worker` of the web app, which the build bundles into one file
self.onconnect = (event) => {
  const port = event.ports[0];
  port.onmessage = () => {
    port.postMessage({ origin: self.origin, isSecureContext: self.isSecureContext, value: 'pong' });
  };
};
