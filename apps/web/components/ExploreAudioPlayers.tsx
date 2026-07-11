import { Card, Stack, Text, ThemeIcon } from "@mantine/core";
import { IconVolume } from "@tabler/icons-react";
import type { ExplorePostMediaItem } from "@/lib/explore";

type ExploreAudioPlayersProps = {
  items: ExplorePostMediaItem[];
  prominent?: boolean;
};

export function ExploreAudioPlayers({ items, prominent = false }: ExploreAudioPlayersProps) {
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
            >
              Your browser does not support audio playback.
            </audio>
          </Stack>
        ))}
      </Stack>
    </Card>
  );
}
