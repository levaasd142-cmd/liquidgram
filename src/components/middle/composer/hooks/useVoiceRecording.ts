import { useEffect, useRef, useState } from '../../../../lib/teact/teact';
import { getActions } from '../../../../global';

import { IS_SAFARI, IS_VOICE_RECORDING_SUPPORTED } from '../../../../util/browser/windowEnvironment';
import { createCallbackManager } from '../../../../util/callbacks';
import captureEscKeyListener from '../../../../util/captureEscKeyListener';
import * as voiceRecording from '../../../../util/voiceRecording';

import useLastCallback from '../../../../hooks/useLastCallback';

type PeakListener = (peak: number) => void;

const useVoiceRecording = () => {
  const recordButtonRef = useRef<HTMLButtonElement>();
  const [activeVoiceRecording, setActiveVoiceRecording] = useState<voiceRecording.ActiveRecording | undefined>();
  const [isRecordingPaused, setIsRecordingPaused] = useState(false);
  const [isViewOnceEnabled, setIsViewOnceEnabled] = useState(false);
  const peakCallbacks = useRef(createCallbackManager<PeakListener>()).current;
  const isStartingRef = useRef(false);
  // Stopping or cancelling while the microphone starts discards the recording that starts
  const startTokenRef = useRef(0);

  useEffect(() => {
    if (IS_SAFARI && IS_VOICE_RECORDING_SUPPORTED) {
      void voiceRecording.init();
    }
  }, []);

  // Resolves with whether a recording started
  const startRecordingVoice = useLastCallback(async () => {
    if (isStartingRef.current) return false;

    isStartingRef.current = true;
    const token = ++startTokenRef.current;
    try {
      const recording = await voiceRecording.start(peakCallbacks.runCallbacks);
      if (token !== startTokenRef.current) {
        void recording.stop(true).catch(() => undefined);
        return false;
      }

      setIsRecordingPaused(false);
      setActiveVoiceRecording(recording);
      return true;
    } catch (err) {
      if (token !== startTokenRef.current) return false;

      if (err instanceof DOMException && (err.name === 'NotAllowedError' || err.name === 'NotFoundError')) {
        getActions().showNotification({ message: { key: 'VoiceRecordMicError' } });
        return false;
      }
      // eslint-disable-next-line no-console
      console.error(err);
      return false;
    } finally {
      isStartingRef.current = false;
    }
  });

  const pauseRecordingVoice = useLastCallback(async () => {
    if (!activeVoiceRecording) return;

    try {
      await activeVoiceRecording.pause();
      setIsRecordingPaused(true);
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error(err);
    }
  });

  const resumeRecordingVoice = useLastCallback(() => {
    if (!activeVoiceRecording) return;

    activeVoiceRecording.resume();
    setIsRecordingPaused(false);
  });

  const stopRecordingVoice = useLastCallback((shouldSkipMinTime?: boolean) => {
    startTokenRef.current++;
    if (!activeVoiceRecording) {
      return undefined;
    }

    setActiveVoiceRecording(undefined);
    setIsRecordingPaused(false);

    try {
      return activeVoiceRecording.stop(shouldSkipMinTime).catch((err): undefined => {
        // eslint-disable-next-line no-console
        console.error(err);
        return undefined;
      });
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error(err);
      return undefined;
    }
  });

  const cancelRecordingVoice = useLastCallback(() => {
    void stopRecordingVoice(true);
  });

  const toggleViewOnceEnabled = useLastCallback(() => {
    setIsViewOnceEnabled(!isViewOnceEnabled);
  });

  const subscribeToRecordingPeaks = useLastCallback((listener: PeakListener) => {
    return peakCallbacks.addCallback(listener);
  });

  useEffect(() => {
    return activeVoiceRecording ? captureEscKeyListener(cancelRecordingVoice) : undefined;
  }, [activeVoiceRecording, cancelRecordingVoice]);

  return {
    startRecordingVoice,
    pauseRecordingVoice,
    resumeRecordingVoice,
    stopRecordingVoice,
    cancelRecordingVoice,
    toggleViewOnceEnabled,
    subscribeToRecordingPeaks,
    activeVoiceRecording,
    isRecordingPaused,
    recordButtonRef,
    isViewOnceEnabled,
    setIsViewOnceEnabled,
  };
};

export default useVoiceRecording;
