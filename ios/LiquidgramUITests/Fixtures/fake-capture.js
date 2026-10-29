// Stands in for what the CI simulator lacks for recording messages: a microphone, and the app's round video recorder
// for builds whose bridge.js does not have one yet. The tests inject it at document start through
// `LIQUIDGRAM_TEST_USER_SCRIPT`, before the app's scripts.
// - `getUserMedia` for audio returns a quiet tone, so a recording starts without hardware and without the permission
//   prompt. A nearly transparent text, "Test microphone: opened N, live M", tells the tests how often the page opened
//   the microphone and how many of its tracks the page has not stopped yet.
// - `window.__liquidgramNative.recordRoundVideo`, which the page needs to offer video messages, resolves with `null` as
//   a cancelled recording. bridge.js replaces it when the app has the recorder.
(() => {
  'use strict';

  const STATUS_PREFIX = 'Test microphone';
  const TONE_FREQUENCY = 440;
  const TONE_GAIN = 0.05;
  const RECORDER_ANSWER_DELAY = 300;

  // Oscillators of the tracks that are not stopped yet, by track id: WebKit may hand out new wrappers for a track
  const oscillatorsByTrackId = new Map();
  let opened = 0;
  let audioContext;
  let statusElement;

  fakeMicrophone();
  provideRoundVideoRecorder();

  function fakeMicrophone() {
    if (typeof MediaDevices !== 'function' || typeof MediaStreamTrack !== 'function') return;

    const { getUserMedia } = MediaDevices.prototype;
    MediaDevices.prototype.getUserMedia = function (constraints) {
      if (!constraints || !constraints.audio || constraints.video) {
        return getUserMedia.call(this, constraints);
      }

      return Promise.resolve(createToneStream());
    };

    const { stop } = MediaStreamTrack.prototype;
    MediaStreamTrack.prototype.stop = function () {
      const oscillator = oscillatorsByTrackId.get(this.id);
      if (oscillator) {
        oscillatorsByTrackId.delete(this.id);
        oscillator.stop();
        updateStatus();
      }
      return stop.call(this);
    };
  }

  function createToneStream() {
    audioContext = audioContext || new AudioContext();
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();
    const destination = audioContext.createMediaStreamDestination();
    oscillator.frequency.value = TONE_FREQUENCY;
    gain.gain.value = TONE_GAIN;
    oscillator.connect(gain);
    gain.connect(destination);
    oscillator.start();
    void audioContext.resume();

    const { stream } = destination;
    stream.getTracks().forEach((track) => {
      oscillatorsByTrackId.set(track.id, oscillator);
    });
    opened += 1;
    updateStatus();
    return stream;
  }

  function updateStatus() {
    if (!document.body) return;

    if (!statusElement) {
      statusElement = document.createElement('span');
      // Nearly transparent at the top left corner, under the status bar, where it covers no control
      statusElement.style.cssText = 'position: fixed; z-index: 1; top: 0; left: 0; font-size: 8px; line-height: 1; '
        + 'opacity: 0.02; pointer-events: none;';
      document.body.appendChild(statusElement);
    }
    statusElement.textContent = `${STATUS_PREFIX}: opened ${opened}, live ${oscillatorsByTrackId.size}`;
  }

  // The app sets `window.__liquidgramNative` after this script and before bridge.js, so the recorder goes onto the
  // object it sets
  function provideRoundVideoRecorder() {
    let native;
    Object.defineProperty(window, '__liquidgramNative', {
      configurable: true,
      enumerable: true,
      get() {
        return native;
      },
      set(value) {
        native = value;
        if (native && typeof native.recordRoundVideo !== 'function') {
          native.recordRoundVideo = () => new Promise((resolve) => {
            setTimeout(() => resolve(null), RECORDER_ANSWER_DELAY);
          });
          native.releaseMedia = () => {};
        }
      },
    });
  }
})();
