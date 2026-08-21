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

export function buildVisualMediaPrompt(
  visualMediaItems: VisualMediaDescriptor[],
  hasVideo: boolean,
  resolvedImageCount: number,
  hasVideoAudio = false,
): string | null {
  if (
    visualMediaItems.length === resolvedImageCount &&
    visualMediaItems.length > 0
  ) {
    const includesVideo = visualMediaItems.some((item) =>
      item.kind === "video_frame"
    );
    const lines = visualMediaItems.map((item, index) => {
      const inputNumber = index + 1;
      if (item.kind === "video_frame") {
        const clipNumber = (item.clipIndex ?? 0) + 1;
        const frameNumber = (item.frameIndex ?? index) + 1;
        return `- Visual input ${inputNumber}: sampled video frame ${frameNumber} from video clip ${clipNumber}.`;
      }

      const sourceNumber = (item.sourceIndex ?? index) + 1;
      const photoLabel =
        `- Visual input ${inputNumber}: still photo ${sourceNumber}.`;
      if (!item.focusRegion) return photoLabel;

      const { x, y, width, height } = item.focusRegion;
      return `${photoLabel} A client-side saliency hint falls inside top-left-normalized bounds x=${
        x.toFixed(4)
      }, y=${y.toFixed(4)}, width=${width.toFixed(4)}, height=${
        height.toFixed(4)
      } in this same photo. Treat these bounds as a tentative attention hint, not as proof of the intended subject. Verify them against the whole frame's relative scale, centrality, focus, and framing. If the dominant subject is non-biological, do not promote incidental or background biology inside or outside the hinted region.`;
    });

    const promptLines = includesVideo
      ? [
        "This scan includes a short user-recorded video. The visual evidence comes from ordered sampled frames from that video, with any listed still photos treated as separate evidence from the same scan.",
      ]
      : [
        "The following visual inputs are ordered still photos from the same scan:",
      ];

    promptLines.push(
      ...lines,
    );

    if (includesVideo) {
      promptLines.push(
        hasVideoAudio
          ? "Analyze the sampled visual frames and accompanying audio as evidence from that video."
          : "Analyze the sampled visual frames as evidence from that video.",
        "When writing user-facing reasoning for this video scan, do not describe the video-derived evidence as images, photos, or an image set.",
      );
    }

    return promptLines.join("\n");
  }

  if (hasVideo && resolvedImageCount > 0) {
    return [
      "This scan includes a short user-recorded video. The visual evidence comes from ordered sampled frames from that video.",
      hasVideoAudio
        ? "Analyze the sampled visual frames and accompanying audio as evidence from that video."
        : "Analyze the sampled visual frames as evidence from that video.",
      "When writing user-facing reasoning for this video scan, do not describe the video-derived evidence as images, photos, or an image set.",
    ].join("\n");
  }

  return null;
}

export type AudioMediaDescriptor = {
  kind: "audio" | "video_audio";
  sourceIndex?: number;
  clipIndex?: number;
};

export type OwnerObservationContext = {
  freeText: string;
  /** Foundation's default Codable Date representation (seconds since 2001-01-01). */
  addedAt?: number;
};

export type OwnerMediaTimelineItem =
  | { kind: "image"; sourceIndex: number }
  | { kind: "audio"; audioInputIndex: number; sourceIndex: number }
  | { kind: "video"; clipIndex: number }
  | { kind: "description"; contextIndex: number };

export type OwnerMediaTimelineValidation =
  | { present: false; timeline: null; error: null }
  | { present: true; timeline: null; error: string }
  | { present: true; timeline: OwnerMediaTimelineItem[]; error: null };

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
  }
  | { description: { _0: OwnerObservationContext } };

export function durableAudioInputIndexes(
  ownerMediaTimeline: OwnerMediaTimelineItem[] | null,
  audioInputCount: number,
): number[] {
  if (!ownerMediaTimeline) {
    return Array.from({ length: audioInputCount }, (_, index) => index);
  }
  return ownerMediaTimeline
    .filter((
      item,
    ): item is Extract<OwnerMediaTimelineItem, { kind: "audio" }> =>
      item.kind === "audio"
    )
    .sort((lhs, rhs) => lhs.sourceIndex - rhs.sourceIndex)
    .map((item) => item.audioInputIndex);
}

export function descriptorsForProcessedAudioInputs(
  descriptors: AudioMediaDescriptor[],
  processedInputIndexes: number[],
): AudioMediaDescriptor[] {
  return processedInputIndexes.flatMap((index) =>
    descriptors[index] ? [descriptors[index]] : []
  );
}

/**
 * Persists the conservative audio role used by replay and post-insert recovery.
 *
 * Without a validated owner timeline, descriptor roles are not deletion authority.
 * Recording every resolved input as unindexed standalone audio makes the durable
 * intent agree with the URLs retained by the legacy write path and prevents a later
 * recovery attempt from reclassifying or deleting an unproven clip.
 */
export function audioDescriptorsForDurableIntent(
  ownerMediaTimeline: OwnerMediaTimelineItem[] | null,
  descriptors: AudioMediaDescriptor[],
  resolvedAudioCount: number,
): AudioMediaDescriptor[] {
  if (ownerMediaTimeline) return descriptors;
  return Array.from(
    { length: resolvedAudioCount },
    (): AudioMediaDescriptor => ({ kind: "audio" }),
  );
}

function optionalIndex(value: unknown): number | undefined {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0
    ? value
    : undefined;
}

function cleanText(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export function normalizeOwnerObservationContexts(
  rawContexts: unknown,
): OwnerObservationContext[] {
  if (!Array.isArray(rawContexts)) return [];
  return rawContexts.flatMap((rawContext): OwnerObservationContext[] => {
    if (
      !rawContext || typeof rawContext !== "object" ||
      Array.isArray(rawContext)
    ) {
      return [];
    }
    const context = rawContext as Record<string, unknown>;
    const freeText = cleanText(context.freeText ?? context.free_text);
    if (!freeText) return [];
    const rawAddedAt = context.addedAt ?? context.added_at;
    let addedAt: number | undefined;
    if (typeof rawAddedAt === "number" && Number.isFinite(rawAddedAt)) {
      addedAt = rawAddedAt;
    } else if (typeof rawAddedAt === "string") {
      const unixMilliseconds = Date.parse(rawAddedAt);
      if (Number.isFinite(unixMilliseconds)) {
        // ObservationContext uses Foundation's default Codable Date format.
        addedAt = unixMilliseconds / 1_000 - 978_307_200;
      }
    }
    return [{ freeText, ...(addedAt == null ? {} : { addedAt }) }];
  });
}

function exactKeys(
  item: Record<string, unknown>,
  allowed: readonly string[],
): boolean {
  const allowedKeys = new Set(allowed);
  return Object.keys(item).every((key) => allowedKeys.has(key));
}

function hasExactIndexes(actual: number[], expectedCount: number): boolean {
  if (
    actual.length !== expectedCount || new Set(actual).size !== actual.length
  ) {
    return false;
  }
  return actual.slice().sort((lhs, rhs) => lhs - rhs).every((value, index) =>
    value === index
  );
}

/**
 * Validates the untrusted owner-visible timeline before quota reservation or media promotion.
 * A present timeline must be complete: every durable owner item is referenced exactly once,
 * and every audio reference agrees with the descriptor at its raw request input index.
 */
export function validateOwnerMediaTimeline(input: {
  rawTimeline: unknown;
  visualMediaItems: VisualMediaDescriptor[];
  resolvedImageCount: number;
  audioMediaItems: AudioMediaDescriptor[];
  resolvedAudioCount: number;
  videoCount: number;
  observationContextCount: number;
}): OwnerMediaTimelineValidation {
  if (input.rawTimeline == null) {
    return { present: false, timeline: null, error: null };
  }
  if (!Array.isArray(input.rawTimeline)) {
    return {
      present: true,
      timeline: null,
      error: "ownerMediaTimeline must be an array.",
    };
  }
  const expectedOwnerItemCount =
    input.visualMediaItems.filter((item) => item.kind === "image").length +
    input.audioMediaItems.filter((item) => item.kind === "audio").length +
    input.videoCount + input.observationContextCount;
  if (
    input.rawTimeline.length !== expectedOwnerItemCount ||
    input.rawTimeline.length > 64
  ) {
    return {
      present: true,
      timeline: null,
      error: "ownerMediaTimeline does not cover the submitted owner media.",
    };
  }
  if (
    input.resolvedImageCount > 0 &&
    input.visualMediaItems.length !== input.resolvedImageCount
  ) {
    return {
      present: true,
      timeline: null,
      error: "visualMediaItems must identify every visual input.",
    };
  }
  if (
    input.resolvedAudioCount > 0 &&
    input.audioMediaItems.length !== input.resolvedAudioCount
  ) {
    return {
      present: true,
      timeline: null,
      error: "audioMediaItems must identify every audio input.",
    };
  }

  const expectedImageIndexes = input.visualMediaItems.flatMap((item) =>
    item.kind === "image" && item.sourceIndex != null ? [item.sourceIndex] : []
  );
  const expectedAudioIndexes = input.audioMediaItems.flatMap((item, index) =>
    item.kind === "audio" ? [index] : []
  );
  const expectedAudioSourceIndexes = input.audioMediaItems.flatMap((item) =>
    item.kind === "audio" && item.sourceIndex != null ? [item.sourceIndex] : []
  );
  const videoAudioClipIndexes = input.audioMediaItems.flatMap((item) =>
    item.kind === "video_audio" && item.clipIndex != null
      ? [item.clipIndex]
      : []
  );
  if (
    !hasExactIndexes(expectedImageIndexes, expectedImageIndexes.length) ||
    !hasExactIndexes(
      expectedAudioSourceIndexes,
      expectedAudioSourceIndexes.length,
    ) || new Set(videoAudioClipIndexes).size !== videoAudioClipIndexes.length
  ) {
    return {
      present: true,
      timeline: null,
      error:
        "Media source indices must be unique zero-based ordinals, with at most one video_audio input per clip.",
    };
  }
  for (const item of input.visualMediaItems) {
    if (
      item.kind === "image" && item.sourceIndex == null ||
      item.kind === "video_frame" &&
        (item.clipIndex == null || item.clipIndex >= input.videoCount)
    ) {
      return {
        present: true,
        timeline: null,
        error: "visualMediaItems contains an invalid owner reference.",
      };
    }
  }
  for (const item of input.audioMediaItems) {
    if (
      item.kind === "audio" && item.sourceIndex == null ||
      item.kind === "video_audio" &&
        (item.clipIndex == null || item.clipIndex >= input.videoCount)
    ) {
      return {
        present: true,
        timeline: null,
        error: "audioMediaItems contains an invalid owner reference.",
      };
    }
  }

  const timeline: OwnerMediaTimelineItem[] = [];
  const seenImages = new Set<number>();
  const seenAudioInputs = new Set<number>();
  const seenAudioSources = new Set<number>();
  const seenVideos = new Set<number>();
  const seenContexts = new Set<number>();

  for (const rawItem of input.rawTimeline) {
    if (!rawItem || typeof rawItem !== "object" || Array.isArray(rawItem)) {
      return {
        present: true,
        timeline: null,
        error: "Invalid owner timeline item.",
      };
    }
    const item = rawItem as Record<string, unknown>;
    if (item.kind === "image") {
      const sourceIndex = optionalIndex(item.sourceIndex ?? item.source_index);
      if (
        sourceIndex == null || !expectedImageIndexes.includes(sourceIndex) ||
        seenImages.has(sourceIndex) ||
        !exactKeys(item, ["kind", "sourceIndex", "source_index"])
      ) {
        return {
          present: true,
          timeline: null,
          error: "Invalid owner image reference.",
        };
      }
      seenImages.add(sourceIndex);
      timeline.push({ kind: "image", sourceIndex });
      continue;
    }
    if (item.kind === "audio") {
      const audioInputIndex = optionalIndex(
        item.audioInputIndex ?? item.audio_input_index,
      );
      const sourceIndex = optionalIndex(item.sourceIndex ?? item.source_index);
      const descriptor = audioInputIndex == null
        ? undefined
        : input.audioMediaItems[audioInputIndex];
      if (
        audioInputIndex == null || sourceIndex == null ||
        !expectedAudioIndexes.includes(audioInputIndex) ||
        descriptor?.kind !== "audio" ||
        descriptor.sourceIndex !== sourceIndex ||
        seenAudioInputs.has(audioInputIndex) ||
        seenAudioSources.has(sourceIndex) ||
        !exactKeys(item, [
          "kind",
          "audioInputIndex",
          "audio_input_index",
          "sourceIndex",
          "source_index",
        ])
      ) {
        return {
          present: true,
          timeline: null,
          error: "Invalid owner audio reference.",
        };
      }
      seenAudioInputs.add(audioInputIndex);
      seenAudioSources.add(sourceIndex);
      timeline.push({ kind: "audio", audioInputIndex, sourceIndex });
      continue;
    }
    if (item.kind === "video") {
      const clipIndex = optionalIndex(item.clipIndex ?? item.clip_index);
      if (
        clipIndex == null || clipIndex >= input.videoCount ||
        seenVideos.has(clipIndex) ||
        !exactKeys(item, ["kind", "clipIndex", "clip_index"])
      ) {
        return {
          present: true,
          timeline: null,
          error: "Invalid owner video reference.",
        };
      }
      seenVideos.add(clipIndex);
      timeline.push({ kind: "video", clipIndex });
      continue;
    }
    if (item.kind === "description") {
      const contextIndex = optionalIndex(
        item.contextIndex ?? item.context_index,
      );
      if (
        contextIndex == null || contextIndex >= input.observationContextCount ||
        seenContexts.has(contextIndex) ||
        !exactKeys(item, ["kind", "contextIndex", "context_index"])
      ) {
        return {
          present: true,
          timeline: null,
          error: "Invalid owner description reference.",
        };
      }
      seenContexts.add(contextIndex);
      timeline.push({ kind: "description", contextIndex });
      continue;
    }
    return {
      present: true,
      timeline: null,
      error: "Unknown owner timeline item kind.",
    };
  }

  if (
    seenImages.size !== expectedImageIndexes.length ||
    seenAudioInputs.size !== expectedAudioIndexes.length ||
    seenVideos.size !== input.videoCount ||
    seenContexts.size !== input.observationContextCount
  ) {
    return {
      present: true,
      timeline: null,
      error: "ownerMediaTimeline does not cover the submitted owner media.",
    };
  }
  return { present: true, timeline, error: null };
}

function remoteMediaReference(
  url: string,
  sourceIndex?: number,
): StoredMediaReferenceDTO {
  const reference: StoredMediaReferenceDTO = {
    storage: "remoteURL",
    path: url,
  };
  const normalizedIndex = optionalIndex(sourceIndex);
  if (normalizedIndex != null) reference.sourceIndex = normalizedIndex;
  return reference;
}

function cleanUrls(urls: string[]): string[] {
  return urls.map((url) => url.trim());
}

/** Builds the canonical owner-facing mixed-media projection stored in `scans.captured_media`. */
export function buildCapturedMediaManifest(input: {
  imageStorageUrls: string[];
  videoStorageUrls: string[];
  audioStorageUrls: string[];
  allPromotedAudioUrls?: string[];
  visualMediaItems: VisualMediaDescriptor[];
  audioMediaItems: AudioMediaDescriptor[];
  ownerMediaTimeline?: OwnerMediaTimelineItem[] | null;
  observationContexts?: OwnerObservationContext[];
}): SerializedMediaItemDTO[] | null {
  const imageUrls = cleanUrls(input.imageStorageUrls);
  const videoUrls = cleanUrls(input.videoStorageUrls);
  const audioUrls = cleanUrls(input.audioStorageUrls);
  const allAudioUrls = cleanUrls(
    input.allPromotedAudioUrls ?? input.audioStorageUrls,
  );
  const contexts = input.observationContexts ?? [];

  if (input.ownerMediaTimeline) {
    const timelineItems = input.ownerMediaTimeline.flatMap(
      (timelineItem): SerializedMediaItemDTO[] => {
        if (timelineItem.kind === "image") {
          const inputIndex = input.visualMediaItems.findIndex((descriptor) =>
            descriptor.kind === "image" &&
            descriptor.sourceIndex === timelineItem.sourceIndex
          );
          const url = imageUrls[inputIndex];
          return url ? [{ image: { _0: remoteMediaReference(url) } }] : [];
        }
        if (timelineItem.kind === "audio") {
          const url = allAudioUrls[timelineItem.audioInputIndex];
          return url
            ? [{
              audio: {
                _0: remoteMediaReference(url, timelineItem.sourceIndex),
              },
            }]
            : [];
        }
        if (timelineItem.kind === "video") {
          const videoUrl = videoUrls[timelineItem.clipIndex];
          if (!videoUrl) return [];
          const thumbnailInputIndex = input.visualMediaItems.findIndex(
            (descriptor) =>
              descriptor.kind === "video_frame" &&
              descriptor.clipIndex === timelineItem.clipIndex,
          );
          const thumbnailUrl = imageUrls[thumbnailInputIndex];
          return [{
            video: {
              _0: {
                video: remoteMediaReference(videoUrl),
                ...(thumbnailUrl
                  ? { thumbnail: remoteMediaReference(thumbnailUrl) }
                  : {}),
              },
            },
          }];
        }
        const context = contexts[timelineItem.contextIndex];
        return context ? [{ description: { _0: context } }] : [];
      },
    );
    return timelineItems.length > 0 ? timelineItems : null;
  }

  // Legacy clients did not submit an owner timeline. Keep their read-compatible grouped
  // projection, but callers must treat every audio URL as durable because role metadata is
  // not strong enough to authorize deletion.
  const items: SerializedMediaItemDTO[] = [];
  const emittedVideoClipIndexes = new Set<number>();
  if (input.visualMediaItems.length === imageUrls.length) {
    for (const [inputIndex, descriptor] of input.visualMediaItems.entries()) {
      const imageUrl = imageUrls[inputIndex];
      if (!imageUrl) continue;
      if (descriptor.kind === "image") {
        items.push({ image: { _0: remoteMediaReference(imageUrl) } });
        continue;
      }
      const clipIndex = descriptor.clipIndex ?? 0;
      if (emittedVideoClipIndexes.has(clipIndex)) continue;
      const videoUrl = videoUrls[clipIndex];
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

  const standaloneDescriptors = input.audioMediaItems.filter((descriptor) =>
    descriptor.kind === "audio"
  );
  const hasCanonicalIdentity = audioUrls.every((url) => url.length > 0) &&
    standaloneDescriptors.length === audioUrls.length &&
    standaloneDescriptors.every((descriptor, index) =>
      optionalIndex(descriptor.sourceIndex) === index
    );
  const audioItems = audioUrls.flatMap((url, index): SerializedMediaItemDTO[] =>
    url
      ? [{
        audio: {
          _0: remoteMediaReference(
            url,
            hasCanonicalIdentity
              ? standaloneDescriptors[index]?.sourceIndex
              : undefined,
          ),
        },
      }]
      : []
  );
  const descriptionItems = contexts.map((context): SerializedMediaItemDTO => ({
    description: { _0: context },
  }));
  const hasResolvedVisualItems = items.length > 0;
  items.push(...audioItems, ...descriptionItems);

  if (hasResolvedVisualItems) return items;
  if (videoUrls.some(Boolean)) {
    return [
      ...videoUrls.flatMap((url, index): SerializedMediaItemDTO[] => {
        if (!url) return [];
        const thumbnailUrl = imageUrls[index] ?? imageUrls[0];
        return [{
          video: {
            _0: {
              video: remoteMediaReference(url),
              ...(thumbnailUrl
                ? { thumbnail: remoteMediaReference(thumbnailUrl) }
                : {}),
            },
          },
        }];
      }),
      ...audioItems,
      ...descriptionItems,
    ];
  }
  const imageItems = imageUrls.flatMap((url): SerializedMediaItemDTO[] =>
    url ? [{ image: { _0: remoteMediaReference(url) } }] : []
  );
  const legacyItems = [...imageItems, ...audioItems, ...descriptionItems];
  return legacyItems.length > 0 ? legacyItems : null;
}

export function capturedMediaVideoCount(
  capturedMedia: SerializedMediaItemDTO[] | null,
): number {
  return (capturedMedia ?? []).filter((item) => "video" in item).length;
}
