# Transport probe

## iOS 17.0 (iPhone 15)

iOS 17.0 (iPhone 15): main done, verify done. custom scheme 76/84 pass, loopback 83/84 pass

| Check | Custom scheme | Loopback | Detail (custom) |
| --- | --- | --- | --- |
| cleared/clean-start-cache-storage | pass | pass | removed |
| cleared/clean-start-indexeddb | pass | pass | removed |
| cleared/clean-start-local-storage | pass | pass | removed |
| cleared/native-is-app-url | pass | pass | liquidgram-web://app/__probe/features.html?phase=cleared&origin=custom&run=40904323740-17.0 |
| cleared/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| embed/info-iframe-referer | FAIL | pass | (none) |
| embed/native-is-app-url | pass | pass | liquidgram-web://app/__probe/embed.html?phase=main&origin=custom&run=40904323740-17.0 |
| embed/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| features/audio-bundle | pass | pass | {"duration":3.55} |
| features/audio-seek | pass | pass | {"duration":19.98,"seekMs":53,"seekedTo":12,"playedTo":12.34} |
| features/blob-download | pass | pass | {"name":"probe-download.txt","size":25} |
| features/blob-url | pass | pass | {"url":"blob:liquidgram-web://app/54b33c22-e033-4a6b-8b2a-a19290874edc","image":"192x192","canvasBlob":174} |
| features/broadcast-channel | pass | pass | page to page and worker to page delivered |
| features/cache-storage-write | pass | pass | stored 40904323740-17.0 under https://liquidgram.invalid/probe-marker |
| features/classic-script | pass | pass | classic-ok |
| features/compression-streams | pass | pass | gzip 3300 -> 56; deflate 3300 -> 44; deflate-raw 3300 -> 38 |
| features/crypto-random-uuid | pass | pass | b58d1669-1b44-45a3-b6aa-b11166a20640 |
| features/crypto-subtle | pass | pass | SHA-1, SHA-256, AES-GCM, HMAC and PBKDF2 work |
| features/dynamic-import | pass | pass | dyn-ok |
| features/fetch-404 | pass | pass | status 404 |
| features/fetch-abort | pass | pass | aborted after 262144 bytes; aborted after 262144 bytes; aborted after 524288 bytes; aborted after 262144 bytes; aborted  |
| features/fetch-head | pass | pass | {"status":200,"length":6327,"type":"text/html; charset=utf-8"} |
| features/fetch-json | pass | pass | {"status":200,"type":"application/json","cacheControl":"no-cache","length":"58"} |
| features/fetch-range | pass | pass | bytes=100-199 -> 206 100 [bytes 100-199/743192]; bytes=0-1 -> 206 2 [bytes 0-1/743192]; bytes=-100 -> 206 100 [bytes 743 |
| features/fetch-traversal | pass | pass | /..%2FInfo.plist -> 400; /assets%2F..%2F..%2FInfo.plist -> 400; /__probe/..%2F..%2FInfo.plist -> 400; /%2e%2e/Info.plist |
| features/font-load | pass | pass | /assets/KFOlCnqEu92Fr1MmEU9fABc4AMP6lbBP-O0pJf89g.woff2 loaded |
| features/getusermedia-exists | pass | pass | {"getUserMedia":"function","devices":"audioinput,videoinput","MediaRecorder":"function","AudioContext":"function","RTCPe |
| features/history-api | pass | pass | pushState and replaceState work |
| features/image-load | pass | pass | 192x192 |
| features/indexeddb-write | pass | pass | stored 40904323740-17.0 |
| features/info-apis | pass | pass | {"serviceWorker":false,"sharedWorker":"function","notification":"function","clipboard":"function","share":"function","wa |
| features/info-cookie | pass | pass | {"cookie":"","cookieEnabled":true} |
| features/info-cross-origin-fetch | pass | pass | liquidgram-web://other/index.html rejected: Load failed |
| features/info-request-headers | pass | pass | {"status":200,"origin":"liquidgram-web://app","referer":"(none)"} |
| features/info-sharedworker-fetch | FAIL | pass | Error: TypeError: Load failed |
| features/info-sharedworker-importscripts | FAIL | pass | Error: NetworkError: Load failed |
| features/info-sharedworker-module-import | FAIL | pass | Error: shared worker error: Importing a module script failed. |
| features/info-sharedworker-subtle | FAIL | pass | Error: TypeError: undefined is not an object (evaluating 'crypto.subtle.digest') |
| features/injected-scripts | pass | pass | user scripts ran at document start |
| features/local-storage-write | pass | pass | stored 40904323740-17.0 |
| features/module-script | pass | pass | liquidgram-web://app/__probe/features.js |
| features/native-is-app-url | pass | pass | liquidgram-web://app/__probe/features.html?phase=main&origin=custom&run=40904323740-17.0 |
| features/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| features/origin | pass | pass | {"origin":"liquidgram-web://app","selfOrigin":"liquidgram-web://app","href":"liquidgram-web://app/__probe/features.html? |
| features/secure-context | pass | pass | isSecureContext is true |
| features/sharedworker-load | FAIL | pass | Error: runs in null, secure context false |
| features/sharedworker-module-load | FAIL | pass | Error: runs in null, secure context false |
| features/storage-persist | pass | pass | {"persist":false,"persisted":false,"quota":10307921511,"usage":114} |
| features/video-blob | pass | pass | {"duration":20,"seekMs":55,"seekedTo":12.02,"playedTo":12.36,"size":"320x240"} |
| features/video-bundle | pass | pass | {"duration":3,"size":"256x256"} |
| features/video-seek | pass | pass | {"duration":20,"seekMs":49,"seekedTo":12.02,"playedTo":12.36,"size":"320x240"} |
| features/wasm-instantiate | pass | pass | add(2, 3) = 5 |
| features/wasm-streaming | pass | pass | /assets/tlottie-kfyd4UOK.wasm: 16 exports, 0 imports |
| features/web-locks | pass | pass | lock granted |
| features/websocket-telegram | pass | pass | opened in 463 ms, protocol "binary", closed with 1000 |
| features/worker-classic | pass | pass | {"fetch":"200 data-ok","subtle":"SHA-256 ok","importScripts":"helper-ok","origin":"liquidgram-web://app","isSecureContex |
| features/worker-module | pass | pass | {"dynamicImport":"dyn-ok","fetch":"200 data-ok","subtle":"SHA-256 ok","wasm":"16 exports","staticImport":"dep-ok","origi |
| features/worker-websocket | pass | pass | opened in 494 ms, protocol "binary", closed with 1000 |
| features/xhr | pass | pass | {"url":"/assets/decoderWorker.min.wasm","bytes":137424,"type":"application/wasm"} |
| media/audio-seek-repeat | pass | pass | 4/4: #1 seeked in 44 ms; #2 seeked in 46 ms; #3 seeked in 42 ms; #4 seeked in 52 ms |
| media/native-is-app-url | pass | pass | liquidgram-web://app/__probe/media.html?phase=main&origin=custom&run=40904323740-17.0 |
| media/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| media/video-faststart-seek-repeat | pass | pass | 4/4: #1 seeked in 50 ms; #2 seeked in 50 ms; #3 seeked in 53 ms; #4 seeked in 53 ms |
| media/video-paused-seek-repeat | FAIL | FAIL | 0/4: #1 FAILED no seeked (readyState 1, networkState 1); events: loadedmetadata@0.0 seeking@12.0; #2 FAILED no seeked (r |
| media/video-seek-repeat | pass | pass | 4/4: #1 seeked in 54 ms; #2 seeked in 54 ms; #3 seeked in 53 ms; #4 seeked in 58 ms |
| realapp/info-realapp-console-errors | pass | pass | none |
| realapp/info-realapp-environment | pass | pass | {"origin":"liquidgram-web://app","isSecureContext":true,"title":"Liquidgram","isIosApp":true,"hasServiceWorkerController |
| realapp/info-realapp-workers | pass | pass | worker-create SharedWorker liquidgram-web://app/sharedState.worker-C6yEYs3Y.js module / worker-create SharedWorker liqui |
| realapp/native-is-app-url | pass | pass | liquidgram-web://app/ |
| realapp/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| realapp/realapp-api-keys-screen | pass | pass | {"heading":"Liquidgram","text":"Liquidgram Liquidgram is an unofficial client, so it needs your own API keys. Get them f |
| realapp/realapp-gramjs-worker | pass | pass | liquidgram-web://app/worker-Bg7dM0Z1.js answered the ping in 131 ms |
| realapp/realapp-no-uncaught-errors | pass | pass | none |
| realapp/realapp-reload | pass | pass | the API keys screen rendered again after 1.0579999685287476 s |
| realapp/realapp-sharedstate-worker | pass | pass | liquidgram-web://app/sharedState.worker-C6yEYs3Y.js answered |
| realapp/realapp-voice-decoder | pass | pass | 11379 bytes of OGG Opus became 196652 bytes of WAV lasting 2.05 s |
| verify/info-storage-persisted | pass | pass | {"persisted":false} |
| verify/native-is-app-url | pass | pass | liquidgram-web://app/__probe/features.html?phase=verify&origin=custom&run=40904323740-17.0 |
| verify/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| verify/origin | pass | pass | {"origin":"liquidgram-web://app","selfOrigin":"liquidgram-web://app","href":"liquidgram-web://app/__probe/features.html? |
| verify/persist-cache-storage | pass | pass | found 40904323740-17.0 |
| verify/persist-indexeddb | pass | pass | found 40904323740-17.0 |
| verify/persist-local-storage | pass | pass | found 40904323740-17.0 |
| verify/secure-context | pass | pass | isSecureContext is true |

## iOS 18.6 (iPhone 16)

iOS 18.6 (iPhone 16): main done, verify done. custom scheme 76/84 pass, loopback 83/84 pass

| Check | Custom scheme | Loopback | Detail (custom) |
| --- | --- | --- | --- |
| cleared/clean-start-cache-storage | pass | pass | removed |
| cleared/clean-start-indexeddb | pass | pass | removed |
| cleared/clean-start-local-storage | pass | pass | removed |
| cleared/native-is-app-url | pass | pass | liquidgram-web://app/__probe/features.html?phase=cleared&origin=custom&run=40904323740-18. |
| cleared/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| embed/info-iframe-referer | FAIL | pass | (none) |
| embed/native-is-app-url | pass | pass | liquidgram-web://app/__probe/embed.html?phase=main&origin=custom&run=40904323740-18. |
| embed/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| features/audio-bundle | pass | pass | {"duration":3.55} |
| features/audio-seek | pass | pass | {"duration":19.98,"seekMs":57,"seekedTo":12,"playedTo":12.35} |
| features/blob-download | pass | pass | {"name":"probe-download.txt","size":25} |
| features/blob-url | pass | pass | {"url":"blob:liquidgram-web://app/77bee480-5540-44ec-ab10-8e971ae910da","image":"192x192","canvasBlob":174} |
| features/broadcast-channel | pass | pass | page to page and worker to page delivered |
| features/cache-storage-write | pass | pass | stored 40904323740-18. under https://liquidgram.invalid/probe-marker |
| features/classic-script | pass | pass | classic-ok |
| features/compression-streams | pass | pass | gzip 3300 -> 56; deflate 3300 -> 44; deflate-raw 3300 -> 38 |
| features/crypto-random-uuid | pass | pass | 656eedac-47f6-44b5-99b7-dc64c6d86cac |
| features/crypto-subtle | pass | pass | SHA-1, SHA-256, AES-GCM, HMAC and PBKDF2 work |
| features/dynamic-import | pass | pass | dyn-ok |
| features/fetch-404 | pass | pass | status 404 |
| features/fetch-abort | pass | pass | aborted after 262144 bytes; aborted after 262144 bytes; aborted after 262144 bytes; aborted after 262144 bytes; aborted  |
| features/fetch-head | pass | pass | {"status":200,"length":6327,"type":"text/html; charset=utf-8"} |
| features/fetch-json | pass | pass | {"status":200,"type":"application/json","cacheControl":"no-cache","length":"58"} |
| features/fetch-range | pass | pass | bytes=100-199 -> 206 100 [bytes 100-199/743192]; bytes=0-1 -> 206 2 [bytes 0-1/743192]; bytes=-100 -> 206 100 [bytes 743 |
| features/fetch-traversal | pass | pass | /..%2FInfo.plist -> 400; /assets%2F..%2F..%2FInfo.plist -> 400; /__probe/..%2F..%2FInfo.plist -> 400; /%2e%2e/Info.plist |
| features/font-load | pass | pass | /assets/KFOlCnqEu92Fr1MmEU9fABc4AMP6lbBP-O0pJf89g.woff2 loaded |
| features/getusermedia-exists | pass | pass | {"getUserMedia":"function","devices":"audioinput,videoinput","MediaRecorder":"function","AudioContext":"function","RTCPe |
| features/history-api | pass | pass | pushState and replaceState work |
| features/image-load | pass | pass | 192x192 |
| features/indexeddb-write | pass | pass | stored 40904323740-18. |
| features/info-apis | pass | pass | {"serviceWorker":false,"sharedWorker":"function","notification":"function","clipboard":"function","share":"function","wa |
| features/info-cookie | pass | pass | {"cookie":"","cookieEnabled":true} |
| features/info-cross-origin-fetch | pass | pass | liquidgram-web://other/index.html rejected: Load failed |
| features/info-request-headers | pass | pass | {"status":200,"origin":"liquidgram-web://app","referer":"(none)"} |
| features/info-sharedworker-fetch | FAIL | pass | Error: TypeError: Load failed |
| features/info-sharedworker-importscripts | FAIL | pass | Error: NetworkError: Load failed |
| features/info-sharedworker-module-import | FAIL | pass | Error: shared worker error: the script did not load |
| features/info-sharedworker-subtle | FAIL | pass | Error: TypeError: undefined is not an object (evaluating 'crypto.subtle.digest') |
| features/injected-scripts | pass | pass | user scripts ran at document start |
| features/local-storage-write | pass | pass | stored 40904323740-18. |
| features/module-script | pass | pass | liquidgram-web://app/__probe/features.js |
| features/native-is-app-url | pass | pass | liquidgram-web://app/__probe/features.html?phase=main&origin=custom&run=40904323740-18. |
| features/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| features/origin | pass | pass | {"origin":"liquidgram-web://app","selfOrigin":"liquidgram-web://app","href":"liquidgram-web://app/__probe/features.html? |
| features/secure-context | pass | pass | isSecureContext is true |
| features/sharedworker-load | FAIL | pass | Error: runs in null, secure context false |
| features/sharedworker-module-load | FAIL | pass | Error: runs in null, secure context false |
| features/storage-persist | pass | pass | {"persist":false,"persisted":false,"quota":10307921511,"usage":112} |
| features/video-blob | pass | pass | {"duration":20,"seekMs":119,"seekedTo":12.08,"playedTo":12.46,"size":"320x240"} |
| features/video-bundle | pass | pass | {"duration":3,"size":"256x256"} |
| features/video-seek | pass | pass | {"duration":20,"seekMs":152,"seekedTo":12.03,"playedTo":12.36,"size":"320x240"} |
| features/wasm-instantiate | pass | pass | add(2, 3) = 5 |
| features/wasm-streaming | pass | pass | /assets/tlottie-kfyd4UOK.wasm: 16 exports, 0 imports |
| features/web-locks | pass | pass | lock granted |
| features/websocket-telegram | pass | pass | opened in 521 ms, protocol "binary", closed with 1000 |
| features/worker-classic | pass | pass | {"fetch":"200 data-ok","subtle":"SHA-256 ok","importScripts":"helper-ok","origin":"liquidgram-web://app","isSecureContex |
| features/worker-module | pass | pass | {"dynamicImport":"dyn-ok","fetch":"200 data-ok","subtle":"SHA-256 ok","wasm":"16 exports","staticImport":"dep-ok","origi |
| features/worker-websocket | pass | pass | opened in 536 ms, protocol "binary", closed with 1000 |
| features/xhr | pass | pass | {"url":"/assets/decoderWorker.min.wasm","bytes":137424,"type":"application/wasm"} |
| media/audio-seek-repeat | pass | pass | 4/4: #1 seeked in 52 ms; #2 seeked in 52 ms; #3 seeked in 44 ms; #4 seeked in 45 ms |
| media/native-is-app-url | pass | pass | liquidgram-web://app/__probe/media.html?phase=main&origin=custom&run=40904323740-18. |
| media/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| media/video-faststart-seek-repeat | pass | pass | 4/4: #1 seeked in 157 ms; #2 seeked in 166 ms; #3 seeked in 173 ms; #4 seeked in 168 ms |
| media/video-paused-seek-repeat | FAIL | FAIL | 0/4: #1 FAILED no seeked (readyState 1, networkState 1); events: loadedmetadata@0.0 seeking@12.0; #2 FAILED no seeked (r |
| media/video-seek-repeat | pass | pass | 4/4: #1 seeked in 184 ms; #2 seeked in 165 ms; #3 seeked in 163 ms; #4 seeked in 219 ms |
| realapp/info-realapp-console-errors | pass | pass | none |
| realapp/info-realapp-environment | pass | pass | {"origin":"liquidgram-web://app","isSecureContext":true,"title":"Liquidgram","isIosApp":true,"hasServiceWorkerController |
| realapp/info-realapp-workers | pass | pass | worker-create SharedWorker liquidgram-web://app/sharedState.worker-C6yEYs3Y.js module / worker-create SharedWorker liqui |
| realapp/native-is-app-url | pass | pass | liquidgram-web://app/ |
| realapp/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| realapp/realapp-api-keys-screen | pass | pass | {"heading":"Liquidgram","text":"Liquidgram Liquidgram is an unofficial client, so it needs your own API keys. Get them f |
| realapp/realapp-gramjs-worker | pass | pass | liquidgram-web://app/worker-Bg7dM0Z1.js answered the ping in 134 ms |
| realapp/realapp-no-uncaught-errors | pass | pass | none |
| realapp/realapp-reload | pass | pass | the API keys screen rendered again after 1.0639070272445679 s |
| realapp/realapp-sharedstate-worker | pass | pass | liquidgram-web://app/sharedState.worker-C6yEYs3Y.js answered |
| realapp/realapp-voice-decoder | pass | pass | 11379 bytes of OGG Opus became 196652 bytes of WAV lasting 2.05 s |
| verify/info-storage-persisted | pass | pass | {"persisted":false} |
| verify/native-is-app-url | pass | pass | liquidgram-web://app/__probe/features.html?phase=verify&origin=custom&run=40904323740-18. |
| verify/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| verify/origin | pass | pass | {"origin":"liquidgram-web://app","selfOrigin":"liquidgram-web://app","href":"liquidgram-web://app/__probe/features.html? |
| verify/persist-cache-storage | pass | pass | found 40904323740-18. |
| verify/persist-indexeddb | pass | pass | found 40904323740-18. |
| verify/persist-local-storage | pass | pass | found 40904323740-18. |
| verify/secure-context | pass | pass | isSecureContext is true |

## iOS 26.2 (iPhone 16)

iOS 26.2 (iPhone 16): main done, verify done. custom scheme 76/84 pass, loopback 83/84 pass

| Check | Custom scheme | Loopback | Detail (custom) |
| --- | --- | --- | --- |
| cleared/clean-start-cache-storage | pass | pass | removed |
| cleared/clean-start-indexeddb | pass | pass | removed |
| cleared/clean-start-local-storage | pass | pass | removed |
| cleared/native-is-app-url | pass | pass | liquidgram-web://app/__probe/features.html?phase=cleared&origin=custom&run=40904323740-26.2 |
| cleared/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| embed/info-iframe-referer | FAIL | pass | (none) |
| embed/native-is-app-url | pass | pass | liquidgram-web://app/__probe/embed.html?phase=main&origin=custom&run=40904323740-26.2 |
| embed/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| features/audio-bundle | pass | pass | {"duration":3.55} |
| features/audio-seek | pass | pass | {"duration":19.98,"seekMs":44,"seekedTo":12,"playedTo":12.34} |
| features/blob-download | pass | pass | {"name":"probe-download.txt","size":25} |
| features/blob-url | pass | pass | {"url":"blob:liquidgram-web://app/b773e907-5a3d-45f1-9335-7370a283b784","image":"192x192","canvasBlob":174} |
| features/broadcast-channel | pass | pass | page to page and worker to page delivered |
| features/cache-storage-write | pass | pass | stored 40904323740-26.2 under https://liquidgram.invalid/probe-marker |
| features/classic-script | pass | pass | classic-ok |
| features/compression-streams | pass | pass | gzip 3300 -> 56; deflate 3300 -> 44; deflate-raw 3300 -> 38 |
| features/crypto-random-uuid | pass | pass | 7c866fc1-ace2-4704-b659-e310887c41c6 |
| features/crypto-subtle | pass | pass | SHA-1, SHA-256, AES-GCM, HMAC and PBKDF2 work |
| features/dynamic-import | pass | pass | dyn-ok |
| features/fetch-404 | pass | pass | status 404 |
| features/fetch-abort | pass | pass | aborted after 262144 bytes; aborted after 524288 bytes; aborted after 262144 bytes; aborted after 262144 bytes; aborted  |
| features/fetch-head | pass | pass | {"status":200,"length":6327,"type":"text/html; charset=utf-8"} |
| features/fetch-json | pass | pass | {"status":200,"type":"application/json","cacheControl":"no-cache","length":"58"} |
| features/fetch-range | pass | pass | bytes=100-199 -> 206 100 [bytes 100-199/743192]; bytes=0-1 -> 206 2 [bytes 0-1/743192]; bytes=-100 -> 206 100 [bytes 743 |
| features/fetch-traversal | pass | pass | /..%2FInfo.plist -> 400; /assets%2F..%2F..%2FInfo.plist -> 400; /__probe/..%2F..%2FInfo.plist -> 400; /%2e%2e/Info.plist |
| features/font-load | pass | pass | /assets/KFOlCnqEu92Fr1MmEU9fABc4AMP6lbBP-O0pJf89g.woff2 loaded |
| features/getusermedia-exists | pass | pass | {"getUserMedia":"function","devices":"audioinput,videoinput","MediaRecorder":"function","AudioContext":"function","RTCPe |
| features/history-api | pass | pass | pushState and replaceState work |
| features/image-load | pass | pass | 192x192 |
| features/indexeddb-write | pass | pass | stored 40904323740-26.2 |
| features/info-apis | pass | pass | {"serviceWorker":false,"sharedWorker":"function","notification":"function","clipboard":"function","share":"function","wa |
| features/info-cookie | pass | pass | {"cookie":"","cookieEnabled":true} |
| features/info-cross-origin-fetch | pass | pass | liquidgram-web://other/index.html rejected: Load failed |
| features/info-request-headers | pass | pass | {"status":200,"origin":"liquidgram-web://app","referer":"(none)"} |
| features/info-sharedworker-fetch | FAIL | pass | Error: TypeError: Load failed |
| features/info-sharedworker-importscripts | FAIL | pass | Error: NetworkError: Load failed |
| features/info-sharedworker-module-import | FAIL | pass | Error: shared worker error: the script did not load |
| features/info-sharedworker-subtle | FAIL | pass | Error: TypeError: undefined is not an object (evaluating 'crypto.subtle.digest') |
| features/injected-scripts | pass | pass | user scripts ran at document start |
| features/local-storage-write | pass | pass | stored 40904323740-26.2 |
| features/module-script | pass | pass | liquidgram-web://app/__probe/features.js |
| features/native-is-app-url | pass | pass | liquidgram-web://app/__probe/features.html?phase=main&origin=custom&run=40904323740-26.2 |
| features/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| features/origin | pass | pass | {"origin":"liquidgram-web://app","selfOrigin":"liquidgram-web://app","href":"liquidgram-web://app/__probe/features.html? |
| features/secure-context | pass | pass | isSecureContext is true |
| features/sharedworker-load | FAIL | pass | Error: runs in null, secure context false |
| features/sharedworker-module-load | FAIL | pass | Error: runs in null, secure context false |
| features/storage-persist | pass | pass | {"persist":false,"persisted":false,"quota":10307921511,"usage":114} |
| features/video-blob | pass | pass | {"duration":20,"seekMs":70,"seekedTo":12.04,"playedTo":12.36,"size":"320x240"} |
| features/video-bundle | pass | pass | {"duration":3,"size":"256x256"} |
| features/video-seek | pass | pass | {"duration":20,"seekMs":149,"seekedTo":12.03,"playedTo":12.36,"size":"320x240"} |
| features/wasm-instantiate | pass | pass | add(2, 3) = 5 |
| features/wasm-streaming | pass | pass | /assets/tlottie-kfyd4UOK.wasm: 16 exports, 0 imports |
| features/web-locks | pass | pass | lock granted |
| features/websocket-telegram | pass | pass | opened in 1254 ms, protocol "binary", closed with 1000 |
| features/worker-classic | pass | pass | {"fetch":"200 data-ok","subtle":"SHA-256 ok","importScripts":"helper-ok","origin":"liquidgram-web://app","isSecureContex |
| features/worker-module | pass | pass | {"dynamicImport":"dyn-ok","fetch":"200 data-ok","subtle":"SHA-256 ok","wasm":"16 exports","staticImport":"dep-ok","origi |
| features/worker-websocket | pass | pass | opened in 556 ms, protocol "binary", closed with 1000 |
| features/xhr | pass | pass | {"url":"/assets/decoderWorker.min.wasm","bytes":137424,"type":"application/wasm"} |
| media/audio-seek-repeat | pass | pass | 4/4: #1 seeked in 50 ms; #2 seeked in 48 ms; #3 seeked in 52 ms; #4 seeked in 52 ms |
| media/native-is-app-url | pass | pass | liquidgram-web://app/__probe/media.html?phase=main&origin=custom&run=40904323740-26.2 |
| media/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| media/video-faststart-seek-repeat | pass | pass | 4/4: #1 seeked in 146 ms; #2 seeked in 143 ms; #3 seeked in 369 ms; #4 seeked in 160 ms |
| media/video-paused-seek-repeat | FAIL | FAIL | 0/4: #1 FAILED no seeked (readyState 1, networkState 1); events: loadedmetadata@0.0 seeking@12.0; #2 FAILED no seeked (r |
| media/video-seek-repeat | pass | pass | 4/4: #1 seeked in 136 ms; #2 seeked in 402 ms; #3 seeked in 162 ms; #4 seeked in 151 ms |
| realapp/info-realapp-console-errors | pass | pass | none |
| realapp/info-realapp-environment | pass | pass | {"origin":"liquidgram-web://app","isSecureContext":true,"title":"Liquidgram","isIosApp":true,"hasServiceWorkerController |
| realapp/info-realapp-workers | pass | pass | worker-create SharedWorker liquidgram-web://app/sharedState.worker-C6yEYs3Y.js module / worker-create SharedWorker liqui |
| realapp/native-is-app-url | pass | pass | liquidgram-web://app/ |
| realapp/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| realapp/realapp-api-keys-screen | pass | pass | {"heading":"Liquidgram","text":"Liquidgram Liquidgram is an unofficial client, so it needs your own API keys. Get them f |
| realapp/realapp-gramjs-worker | pass | pass | liquidgram-web://app/worker-Bg7dM0Z1.js answered the ping in 113 ms |
| realapp/realapp-no-uncaught-errors | pass | pass | none |
| realapp/realapp-reload | pass | pass | the API keys screen rendered again after 1.053313970565796 s |
| realapp/realapp-sharedstate-worker | pass | pass | liquidgram-web://app/sharedState.worker-C6yEYs3Y.js answered |
| realapp/realapp-voice-decoder | pass | pass | 11379 bytes of OGG Opus became 196652 bytes of WAV lasting 2.05 s |
| verify/info-storage-persisted | pass | pass | {"persisted":false} |
| verify/native-is-app-url | pass | pass | liquidgram-web://app/__probe/features.html?phase=verify&origin=custom&run=40904323740-26.2 |
| verify/native-message-origin | pass | pass | liquidgram-web://app port 0 |
| verify/origin | pass | pass | {"origin":"liquidgram-web://app","selfOrigin":"liquidgram-web://app","href":"liquidgram-web://app/__probe/features.html? |
| verify/persist-cache-storage | pass | pass | found 40904323740-26.2 |
| verify/persist-indexeddb | pass | pass | found 40904323740-26.2 |
| verify/persist-local-storage | pass | pass | found 40904323740-26.2 |
| verify/secure-context | pass | pass | isSecureContext is true |

