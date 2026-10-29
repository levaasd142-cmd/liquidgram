// Checks shared by the workers. Classic workers load this file with `importScripts()`, module workers with a static
// `import`, which runs it for its side effect.
self.__probeWorkerChecks = {
  async fetchData() {
    const response = await fetch('data.json', { cache: 'no-store' });
    const data = await response.json();
    return `${response.status} ${data.probe}`;
  },

  async digest() {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('abc'));
    const first = new Uint8Array(digest)[0];
    if (first !== 0xba) throw new Error(`wrong digest byte ${first}`);
    return 'SHA-256 ok';
  },

  openAndCloseWebSocket(url) {
    return new Promise((resolve, reject) => {
      const startedAt = Date.now();
      const socket = new WebSocket(url, 'binary');
      let isOpen = false;
      const timer = setTimeout(() => {
        socket.close();
        reject(new Error('no open or close within 15 s'));
      }, 15000);
      socket.onopen = () => {
        isOpen = true;
        socket.close(1000);
      };
      socket.onclose = (e) => {
        clearTimeout(timer);
        if (!isOpen) {
          reject(new Error(`closed before open with code ${e.code}`));
          return;
        }
        resolve(`opened in ${Date.now() - startedAt} ms, protocol "${socket.protocol}", closed with ${e.code}`);
      };
    });
  },

  async compileWasm(url) {
    const module = await WebAssembly.compileStreaming(fetch(url));
    return `${WebAssembly.Module.exports(module).length} exports`;
  },

  // Runs named checks and collects their results without stopping at a failure
  async run(checks) {
    const result = {};
    const errors = [];
    for (const [name, check] of Object.entries(checks)) {
      try {
        result[name] = await check();
      } catch (err) {
        errors.push(`${name}: ${err && err.message ? err.message : String(err)}`);
      }
    }
    return { result, errors };
  },
};
