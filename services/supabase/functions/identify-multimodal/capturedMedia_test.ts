import { assertEquals } from "@std/assert";

import {
  buildCapturedMediaManifest,
  type SerializedMediaItemDTO,
} from "./capturedMedia.ts";

Deno.test("captured media preserves standalone audio source identity", () => {
  assertEquals(
    buildCapturedMediaManifest(
      [],
      [],
      [
        "https://media.merian.app/first.wav",
        "https://media.merian.app/second.wav",
      ],
      [],
      [
        { kind: "audio", sourceIndex: 0 },
        { kind: "audio", sourceIndex: 1 },
      ],
    ),
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

Deno.test("captured media pairs filtered standalone descriptors in mixed video audio", () => {
  assertEquals(
    buildCapturedMediaManifest(
      ["https://media.merian.app/poster.webp"],
      ["https://media.merian.app/clip.mp4"],
      ["https://media.merian.app/standalone.wav"],
      [{ kind: "video_frame", clipIndex: 0, frameIndex: 0 }],
      [
        { kind: "video_audio", clipIndex: 0 },
        { kind: "audio", sourceIndex: 0 },
      ],
    ),
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
        audio: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/standalone.wav",
            sourceIndex: 0,
          },
        },
      },
    ],
  );
});

Deno.test("captured media strips every ambiguous standalone audio identity", () => {
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
      { kind: "audio" as const, sourceIndex: 0 },
      { kind: "audio" as const, sourceIndex: -1 },
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
      buildCapturedMediaManifest(
        [],
        [],
        [
          "https://media.merian.app/first.wav",
          "https://media.merian.app/second.wav",
        ],
        [],
        descriptors,
      ),
      expected,
    );
  }
});

Deno.test("captured media strips identity when an audio URL is missing", () => {
  assertEquals(
    buildCapturedMediaManifest(
      [],
      [],
      ["https://media.merian.app/first.wav", "   "],
      [],
      [
        { kind: "audio", sourceIndex: 0 },
        { kind: "audio", sourceIndex: 1 },
      ],
    ),
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

Deno.test("captured media keeps legacy audio unindexed when descriptors are incomplete", () => {
  assertEquals(
    buildCapturedMediaManifest(
      [],
      [],
      [
        "https://media.merian.app/first.wav",
        "https://media.merian.app/second.wav",
      ],
      [],
      [{ kind: "audio", sourceIndex: 0 }],
    ),
    [
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
    ],
  );
});
