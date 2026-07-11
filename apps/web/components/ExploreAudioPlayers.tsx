"use client";

import { Card, Stack, Text, ThemeIcon } from "@mantine/core";
import { IconVolume } from "@tabler/icons-react";
import { useRef } from "react";
import type { ExplorePostMediaItem } from "@/lib/explore";
import { captureAudioTelemetry, markAudioPlaybackStarted } from "@/lib/audioTelemetry";

type ExploreAudioPlayersProps = {
  items: ExplorePostMediaItem[];
  prominent?: boolean;
};

export function ExploreAudioPlayers({ items, prominent = false }: ExploreAudioPlayersProps) {
  const startedItems = useRef(new Set<string>());
  const audioItems = items.filter((item) => item.kind === "audio");
  if (!audioItems.length) return null;

  return (
    <Card withBorder radius={prominent ? 0 : "md"} p={{ base: "md", sm: "lg" }}>
      <Stack gap="md" align={prominent ? "center" : "stretch"}>
        {prominent ? (
          <ThemeIcon size={64} radius="xl" variant="light" aria-hidden="true">
            <IconVolume size={32} />
          </ThemeIcon>
        ) : null}
        <Text fw={700} ta={prominent ? "center" : undefined}>
          {audioItems.length === 1 ? "Field recording" : "Field recordings"}
        </Text>
        {audioItems.map((item, index) => (
          <Stack key={`${item.url}-${item.orderIndex}`} gap={6} w="100%">
            <Text size="sm" c="dimmed" id={`audio-clip-${item.orderIndex}`}>
              Audio clip {index + 1}
            </Text>
            <audio
              controls
              preload="metadata"
              src={item.url}
              aria-labelledby={`audio-clip-${item.orderIndex}`}
              style={{ width: "100%" }}
              onPlay={() => {
                if (!markAudioPlaybackStarted(startedItems.current, item.url)) return;
                captureAudioTelemetry("ExploreAudioPlaybackStarted", audioSurface(prominent));
              }}
              onEnded={() => captureAudioTelemetry("ExploreAudioPlaybackCompleted", audioSurface(prominent))}
              onError={() => captureAudioTelemetry("ExploreAudioPlaybackFailed", audioSurface(prominent))}
            >
              Your browser does not support audio playback.
            </audio>
          </Stack>
        ))}
      </Stack>
    </Card>
  );
}

function audioSurface(prominent: boolean) {
  return prominent ? "detail_audio_header" : "detail_mixed_media";
}
