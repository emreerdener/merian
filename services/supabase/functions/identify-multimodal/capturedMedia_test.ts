import { assertEquals, assertMatch } from "@std/assert";

import {
  audioDescriptorsForDurableIntent,
  buildCapturedMediaManifest,
  descriptorsForProcessedAudioInputs,
  durableAudioInputIndexes,
  normalizeOwnerObservationContexts,
  type SerializedMediaItemDTO,
  validateOwnerMediaTimeline,
} from "./capturedMedia.ts";

Deno.test("owner observation contexts normalize ISO dates for Swift Codable", () => {
  assertEquals(
    normalizeOwnerObservationContexts([
      {
        free_text: "  Near a pond  ",
        added_at: "2026-07-05T12:00:00.000Z",
      },
    ]),
    [{
      freeText: "Near a pond",
      addedAt: Date.parse("2026-07-05T12:00:00.000Z") / 1_000 - 978_307_200,
    }],
  );
});

Deno.test("only a validated owner timeline authorizes companion audio deletion", () => {
  assertEquals(durableAudioInputIndexes(null, 2), [0, 1]);
  assertEquals(
    durableAudioInputIndexes([
      { kind: "video", clipIndex: 0 },
      { kind: "audio", audioInputIndex: 1, sourceIndex: 0 },
    ], 2),
    [1],
  );
});

Deno.test("skipped WAV inputs do not shift later audio descriptors", () => {
  assertEquals(
    descriptorsForProcessedAudioInputs(
      [
        { kind: "video_audio", clipIndex: 0 },
        { kind: "audio", sourceIndex: 0 },
      ],
      [1],
    ),
    [{ kind: "audio", sourceIndex: 0 }],
  );
});

Deno.test("legacy durable intent classifies every unproven audio input as retained", () => {
  assertEquals(
    audioDescriptorsForDurableIntent(
      null,
      [
        { kind: "video_audio", clipIndex: 0 },
        { kind: "audio", sourceIndex: 0 },
      ],
      2,
    ),
    [{ kind: "audio" }, { kind: "audio" }],
  );

  const canonicalTimeline = [
    { kind: "video" as const, clipIndex: 0 },
    {
      kind: "audio" as const,
      audioInputIndex: 1,
      sourceIndex: 0,
    },
  ];
  const canonicalDescriptors = [
    { kind: "video_audio" as const, clipIndex: 0 },
    { kind: "audio" as const, sourceIndex: 0 },
  ];
  assertEquals(
    audioDescriptorsForDurableIntent(
      canonicalTimeline,
      canonicalDescriptors,
      2,
    ),
    canonicalDescriptors,
  );
});

Deno.test("captured media preserves standalone audio source identity", () => {
  assertEquals(
    buildCapturedMediaManifest({
      imageStorageUrls: [],
      videoStorageUrls: [],
      audioStorageUrls: [
        "https://media.merian.app/first.wav",
        "https://media.merian.app/second.wav",
      ],
      visualMediaItems: [],
      audioMediaItems: [
        { kind: "audio", sourceIndex: 0 },
        { kind: "audio", sourceIndex: 1 },
      ],
    }),
    [
      {
        audio: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/first.wav",
            sourceIndex: 0,
          },
        },
      },
      {
        audio: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/second.wav",
            sourceIndex: 1,
          },
        },
      },
    ],
  );
});

Deno.test("legacy captured media preserves every description after grouped media", () => {
  assertEquals(
    buildCapturedMediaManifest({
      imageStorageUrls: [],
      videoStorageUrls: [],
      audioStorageUrls: ["https://media.merian.app/recording.wav"],
      visualMediaItems: [],
      audioMediaItems: [{ kind: "audio", sourceIndex: 0 }],
      observationContexts: [
        { freeText: "First note", addedAt: 807_000_000 },
        { freeText: "Second note" },
      ],
    }),
    [
      {
        audio: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/recording.wav",
            sourceIndex: 0,
          },
        },
      },
      {
        description: {
          _0: { freeText: "First note", addedAt: 807_000_000 },
        },
      },
      {
        description: {
          _0: { freeText: "Second note" },
        },
      },
    ],
  );
});

Deno.test("legacy text-only captured media produces a durable description manifest", () => {
  assertEquals(
    buildCapturedMediaManifest({
      imageStorageUrls: [],
      videoStorageUrls: [],
      audioStorageUrls: [],
      visualMediaItems: [],
      audioMediaItems: [],
      observationContexts: [{ freeText: "Text-only observation" }],
    }),
    [
      {
        description: {
          _0: { freeText: "Text-only observation" },
        },
      },
    ],
  );
});

Deno.test("canonical captured media preserves interleaved video descriptions and audio", () => {
  const visualMediaItems = [
    { kind: "video_frame" as const, clipIndex: 0, frameIndex: 0 },
  ];
  const audioMediaItems = [
    { kind: "video_audio" as const, clipIndex: 0 },
    { kind: "audio" as const, sourceIndex: 0 },
  ];
  const rawTimeline = [
    { kind: "video", clipIndex: 0 },
    { kind: "description", contextIndex: 0 },
    { kind: "audio", audioInputIndex: 1, sourceIndex: 0 },
    { kind: "description", contextIndex: 1 },
  ];
  const validation = validateOwnerMediaTimeline({
    rawTimeline,
    visualMediaItems,
    resolvedImageCount: 1,
    audioMediaItems,
    resolvedAudioCount: 2,
    videoCount: 1,
    observationContextCount: 2,
  });
  assertEquals(validation.error, null);
  assertEquals(
    buildCapturedMediaManifest({
      imageStorageUrls: ["https://media.merian.app/poster.webp"],
      videoStorageUrls: ["https://media.merian.app/clip.mp4"],
      audioStorageUrls: ["https://media.merian.app/standalone.wav"],
      allPromotedAudioUrls: [
        "https://media.merian.app/video-audio.wav",
        "https://media.merian.app/standalone.wav",
      ],
      visualMediaItems,
      audioMediaItems,
      ownerMediaTimeline: validation.timeline,
      observationContexts: [
        { freeText: "First note", addedAt: 807_000_000 },
        { freeText: "Second note" },
      ],
    }),
    [
      {
        video: {
          _0: {
            video: {
              storage: "remoteURL",
              path: "https://media.merian.app/clip.mp4",
            },
            thumbnail: {
              storage: "remoteURL",
              path: "https://media.merian.app/poster.webp",
            },
          },
        },
      },
      {
        description: {
          _0: { freeText: "First note", addedAt: 807_000_000 },
        },
      },
      {
        audio: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/standalone.wav",
            sourceIndex: 0,
          },
        },
      },
      {
        description: {
          _0: { freeText: "Second note" },
        },
      },
    ],
  );
});

Deno.test("owner timeline rejects duplicate and out-of-range references", () => {
  const duplicate = validateOwnerMediaTimeline({
    rawTimeline: [
      { kind: "audio", audioInputIndex: 0, sourceIndex: 0 },
      { kind: "audio", audioInputIndex: 0, sourceIndex: 0 },
    ],
    visualMediaItems: [],
    resolvedImageCount: 0,
    audioMediaItems: [
      { kind: "audio", sourceIndex: 0 },
      { kind: "audio", sourceIndex: 1 },
    ],
    resolvedAudioCount: 2,
    videoCount: 0,
    observationContextCount: 0,
  });
  assertMatch(duplicate.error ?? "", /audio/);

  const outOfRange = validateOwnerMediaTimeline({
    rawTimeline: [{ kind: "description", contextIndex: 1 }],
    visualMediaItems: [],
    resolvedImageCount: 0,
    audioMediaItems: [],
    resolvedAudioCount: 0,
    videoCount: 0,
    observationContextCount: 1,
  });
  assertMatch(outOfRange.error ?? "", /description/);
});

Deno.test("owner timeline rejects missing and noncanonical audio identities", () => {
  const missingDescriptor = validateOwnerMediaTimeline({
    rawTimeline: [],
    visualMediaItems: [],
    resolvedImageCount: 0,
    audioMediaItems: [],
    resolvedAudioCount: 1,
    videoCount: 0,
    observationContextCount: 0,
  });
  assertMatch(missingDescriptor.error ?? "", /audioMediaItems/);

  const duplicateSource = validateOwnerMediaTimeline({
    rawTimeline: [
      { kind: "audio", audioInputIndex: 0, sourceIndex: 0 },
      { kind: "audio", audioInputIndex: 1, sourceIndex: 0 },
    ],
    visualMediaItems: [],
    resolvedImageCount: 0,
    audioMediaItems: [
      { kind: "audio", sourceIndex: 0 },
      { kind: "audio", sourceIndex: 0 },
    ],
    resolvedAudioCount: 2,
    videoCount: 0,
    observationContextCount: 0,
  });
  assertMatch(duplicateSource.error ?? "", /zero-based/);

  const duplicateVideoCompanion = validateOwnerMediaTimeline({
    rawTimeline: [{ kind: "video", clipIndex: 0 }],
    visualMediaItems: [
      { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
    ],
    resolvedImageCount: 1,
    audioMediaItems: [
      { kind: "video_audio", clipIndex: 0 },
      { kind: "video_audio", clipIndex: 0 },
    ],
    resolvedAudioCount: 2,
    videoCount: 1,
    observationContextCount: 0,
  });
  assertMatch(duplicateVideoCompanion.error ?? "", /video_audio/);
});

Deno.test("legacy captured media strips ambiguous standalone audio identity without dropping clips", () => {
  const malformedDescriptorSets = [
    [
      { kind: "audio" as const, sourceIndex: 0 },
      { kind: "audio" as const, sourceIndex: 0 },
    ],
    [
      { kind: "audio" as const, sourceIndex: 0 },
      { kind: "audio" as const, sourceIndex: 1.9 },
    ],
    [
      { kind: "audio" as const, sourceIndex: 1 },
      { kind: "audio" as const, sourceIndex: 2 },
    ],
    [
      { kind: "audio" as const },
      { kind: "audio" as const },
    ],
  ];
  const expected: SerializedMediaItemDTO[] = [
    {
      audio: {
        _0: {
          storage: "remoteURL",
          path: "https://media.merian.app/first.wav",
        },
      },
    },
    {
      audio: {
        _0: {
          storage: "remoteURL",
          path: "https://media.merian.app/second.wav",
        },
      },
    },
  ];

  for (const descriptors of malformedDescriptorSets) {
    assertEquals(
      buildCapturedMediaManifest({
        imageStorageUrls: [],
        videoStorageUrls: [],
        audioStorageUrls: [
          "https://media.merian.app/first.wav",
          "https://media.merian.app/second.wav",
        ],
        visualMediaItems: [],
        audioMediaItems: descriptors,
      }),
      expected,
    );
  }
});

Deno.test("legacy captured media strips identity when an audio URL is missing", () => {
  assertEquals(
    buildCapturedMediaManifest({
      imageStorageUrls: [],
      videoStorageUrls: [],
      audioStorageUrls: ["https://media.merian.app/first.wav", "   "],
      visualMediaItems: [],
      audioMediaItems: [
        { kind: "audio", sourceIndex: 0 },
        { kind: "audio", sourceIndex: 1 },
      ],
    }),
    [
      {
        audio: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/first.wav",
          },
        },
      },
    ],
  );
});
