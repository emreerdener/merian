export type VisualMediaDescriptor = {
  kind: "image" | "video_frame";
  sourceIndex?: number;
  clipIndex?: number;
  frameIndex?: number;
  focusRegion?: {
    x: number;
    y: number;
    width: number;
    height: number;
    source: "vision_objectness";
  };
};

export type AudioMediaDescriptor = {
  kind: "audio" | "video_audio";
  sourceIndex?: number;
  clipIndex?: number;
};

export type StoredMediaReferenceDTO = {
  storage: "remoteURL";
  path: string;
  sourceIndex?: number;
};

export type SerializedMediaItemDTO =
  | { image: { _0: StoredMediaReferenceDTO } }
  | { audio: { _0: StoredMediaReferenceDTO } }
  | {
    video: {
      _0: {
        video: StoredMediaReferenceDTO;
        thumbnail?: StoredMediaReferenceDTO;
      };
    };
  };

function normalizedSourceIndex(value: number | undefined): number | undefined {
  if (value == null || !Number.isSafeInteger(value) || value < 0) {
    return undefined;
  }
  return value;
}

function remoteMediaReference(
  url: string,
  sourceIndex?: number,
): StoredMediaReferenceDTO {
  const reference: StoredMediaReferenceDTO = {
    storage: "remoteURL",
    path: url,
  };
  const normalizedIndex = normalizedSourceIndex(sourceIndex);
  if (normalizedIndex != null) reference.sourceIndex = normalizedIndex;
  return reference;
}

/**
 * Builds the owner-facing mixed-media projection stored in `scans.captured_media`.
 * Standalone audio URLs have already been separated from inference-only video audio,
 * so their filtered descriptors can safely carry the original clip identity.
 */
export function buildCapturedMediaManifest(
  imageStorageUrls: string[],
  videoStorageUrls: string[],
  audioStorageUrls: string[],
  visualMediaItems: VisualMediaDescriptor[],
  audioMediaItems: AudioMediaDescriptor[],
): SerializedMediaItemDTO[] | null {
  const sanitizedImageUrls = imageStorageUrls
    .map((url) => url.trim())
    .filter((url) => url.length > 0);
  const sanitizedVideoUrls = videoStorageUrls
    .map((url) => url.trim())
    .filter((url) => url.length > 0);
  const sanitizedAudioUrls = audioStorageUrls
    .map((url) => url.trim())
    .filter((url) => url.length > 0);

  if (
    sanitizedImageUrls.length === 0 && sanitizedVideoUrls.length === 0 &&
    sanitizedAudioUrls.length === 0
  ) {
    return null;
  }

  const items: SerializedMediaItemDTO[] = [];
  const emittedVideoClipIndexes = new Set<number>();

  if (visualMediaItems.length === sanitizedImageUrls.length) {
    for (const [inputIndex, descriptor] of visualMediaItems.entries()) {
      const imageUrl = sanitizedImageUrls[inputIndex];
      if (!imageUrl) continue;

      if (descriptor.kind === "image") {
        items.push({ image: { _0: remoteMediaReference(imageUrl) } });
        continue;
      }

      const clipIndex = descriptor.clipIndex ?? 0;
      if (emittedVideoClipIndexes.has(clipIndex)) continue;

      const videoUrl = sanitizedVideoUrls[clipIndex];
      if (!videoUrl) continue;

      emittedVideoClipIndexes.add(clipIndex);
      items.push({
        video: {
          _0: {
            video: remoteMediaReference(videoUrl),
            thumbnail: remoteMediaReference(imageUrl),
          },
        },
      });
    }
  }

  const emittedVisualItemCount = items.length;
  const standaloneAudioDescriptors = audioMediaItems.filter((descriptor) =>
    descriptor.kind === "audio"
  );
  const hasCanonicalIdentityForEveryStandaloneClip =
    standaloneAudioDescriptors.length === sanitizedAudioUrls.length &&
    standaloneAudioDescriptors.every((descriptor, index) =>
      normalizedSourceIndex(descriptor.sourceIndex) === index
    );
  const standaloneAudioItems = sanitizedAudioUrls.map(
    (audioUrl, index): SerializedMediaItemDTO => ({
      audio: {
        _0: remoteMediaReference(
          audioUrl,
          hasCanonicalIdentityForEveryStandaloneClip
            ? standaloneAudioDescriptors[index]?.sourceIndex
            : undefined,
        ),
      },
    }),
  );
  items.push(...standaloneAudioItems);

  if (emittedVisualItemCount > 0) {
    return items;
  }

  if (sanitizedVideoUrls.length > 0) {
    const videoItems = sanitizedVideoUrls.map((videoUrl, index) => {
      const thumbnailUrl = sanitizedImageUrls[index] ?? sanitizedImageUrls[0];
      const video: SerializedMediaItemDTO = {
        video: {
          _0: {
            video: remoteMediaReference(videoUrl),
          },
        },
      };

      if (thumbnailUrl) {
        video.video._0.thumbnail = remoteMediaReference(thumbnailUrl);
      }

      return video;
    });
    return [...videoItems, ...standaloneAudioItems];
  }

  const imageItems = sanitizedImageUrls.map(
    (imageUrl): SerializedMediaItemDTO => ({
      image: { _0: remoteMediaReference(imageUrl) },
    }),
  );
  return [...imageItems, ...standaloneAudioItems];
}

export function capturedMediaVideoCount(
  capturedMedia: SerializedMediaItemDTO[] | null,
): number {
  return (capturedMedia ?? []).filter((item) => "video" in item).length;
}
