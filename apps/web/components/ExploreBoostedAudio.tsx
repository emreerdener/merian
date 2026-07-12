"use client";

import { Button, Group, Stack, Text } from "@mantine/core";
import { IconVolume, IconVolume2 } from "@tabler/icons-react";
import { useEffect, useRef, useState } from "react";
import { captureAudioTelemetry, markAudioPlaybackStarted } from "@/lib/audioTelemetry";
import { webAudioProxyPath } from "@/lib/audioProxy";

type ExploreBoostedAudioProps = {
  audioUrl: string;
  postId: string;
  altText: string;
};

type BoostState = "original" | "boosting" | "boosted";

export function ExploreBoostedAudio({ audioUrl, postId, altText }: ExploreBoostedAudioProps) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const contextRef = useRef<AudioContext | null>(null);
  const gainRef = useRef<GainNode | null>(null);
  const preparedRef = useRef(false);
  const restoreStartedRef = useRef(false);
  const startedItems = useRef(new Set<string>());
  const [boostState, setBoostState] = useState<BoostState>("original");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const preferenceKey = `merian_web_audio_boost_v1:${postId}`;

  useEffect(() => {
    if (restoreStartedRef.current) return;
    restoreStartedRef.current = true;
    try {
      if (window.localStorage.getItem(preferenceKey) === "enabled") {
        void enableBoost(false);
      }
    } catch {
      // Private browsing may make local storage unavailable.
    }
    return () => {
      void contextRef.current?.close();
    };
  }, [preferenceKey]);

  async function prepareGraph(audio: HTMLAudioElement) {
    if (preparedRef.current) return;
    const wasPaused = audio.paused;
    const currentTime = audio.currentTime;
    audio.src = webAudioProxyPath(audioUrl);
    const AudioContextType = window.AudioContext;
    const context = new AudioContextType();
    const source = context.createMediaElementSource(audio);
    const highPass = context.createBiquadFilter();
    highPass.type = "highpass";
    highPass.frequency.value = 35;
    const gain = context.createGain();
    const limiter = context.createDynamicsCompressor();
    limiter.threshold.value = -3;
    limiter.knee.value = 6;
    limiter.ratio.value = 20;
    limiter.attack.value = 0.003;
    limiter.release.value = 0.25;
    source.connect(highPass).connect(gain).connect(limiter).connect(context.destination);
    contextRef.current = context;
    gainRef.current = gain;
    preparedRef.current = true;
    void context.resume();
    audio.load();
    await waitForMetadata(audio);
    audio.currentTime = Math.min(currentTime, Number.isFinite(audio.duration) ? audio.duration : currentTime);
    if (!wasPaused) await audio.play();
  }

  async function enableBoost(showFeedback: boolean) {
    const audio = audioRef.current;
    if (!audio) return;
    setErrorMessage(null);
    if (showFeedback) setBoostState("boosting");
    try {
      await prepareGraph(audio);
      if (gainRef.current) gainRef.current.gain.value = 2.8;
      setBoostState("boosted");
      try {
        window.localStorage.setItem(preferenceKey, "enabled");
      } catch {}
      if (showFeedback) captureAudioTelemetry("ExploreAudioBoostChanged", "detail_media_carousel");
    } catch {
      setBoostState("original");
      if (showFeedback) setErrorMessage("Boost unavailable. Original audio is playing.");
    }
  }

  function disableBoost() {
    if (gainRef.current) gainRef.current.gain.value = 1;
    setBoostState("original");
    setErrorMessage(null);
    try {
      window.localStorage.removeItem(preferenceKey);
    } catch {}
    captureAudioTelemetry("ExploreAudioBoostChanged", "detail_media_carousel");
  }

  return (
    <Stack gap={8}>
      <Group justify="space-between" gap="sm">
        <Text c="white" size="sm" fw={700}>Field recording</Text>
        <Button
          size="compact-xs"
          variant={boostState === "boosted" ? "filled" : "default"}
          leftSection={boostState === "boosted" ? <IconVolume2 size={14} /> : <IconVolume size={14} />}
          loading={boostState === "boosting"}
          onClick={() => boostState === "boosted" ? disableBoost() : void enableBoost(true)}
          aria-label={boostState === "boosted" ? "Turn off audio boost" : "Boost audio"}
        >
          {boostState === "boosted" ? "Boosted audio" : boostState === "boosting" ? "Boosting audio…" : "Boost audio"}
        </Button>
      </Group>
      <audio
        ref={audioRef}
        controls
        preload="metadata"
        src={audioUrl}
        aria-label={`Play field recording for ${altText}`}
        style={{ width: "100%", display: "block" }}
        onPlay={() => {
          void contextRef.current?.resume();
          if (!markAudioPlaybackStarted(startedItems.current, audioUrl)) return;
          captureAudioTelemetry("ExploreAudioPlaybackStarted", "detail_media_carousel");
        }}
        onEnded={() => captureAudioTelemetry("ExploreAudioPlaybackCompleted", "detail_media_carousel")}
        onError={() => captureAudioTelemetry("ExploreAudioPlaybackFailed", "detail_media_carousel")}
      >
        Your browser does not support audio playback.
      </audio>
      {errorMessage ? <Text c="white" size="xs">{errorMessage}</Text> : null}
    </Stack>
  );
}

function waitForMetadata(audio: HTMLAudioElement): Promise<void> {
  if (audio.readyState >= HTMLMediaElement.HAVE_METADATA) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      audio.removeEventListener("loadedmetadata", loaded);
      audio.removeEventListener("error", failed);
    };
    const loaded = () => { cleanup(); resolve(); };
    const failed = () => { cleanup(); reject(new Error("Audio failed to load")); };
    audio.addEventListener("loadedmetadata", loaded, { once: true });
    audio.addEventListener("error", failed, { once: true });
  });
}
