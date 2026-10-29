// Echo worker for the `worker` check of `selftest.js`. `run-ui-tests.sh` copies it into the web build of the test app
// only, where the local server serves it from the app's origin like the web app's own workers.
self.onmessage = (e) => {
  self.postMessage({
    pong: e.data && e.data.ping,
    isSecureContext: self.isSecureContext,
  });
};
