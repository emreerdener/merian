import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { PublicHttpError } from "../_shared/http.ts";
import {
  assertRestoredMediaLedgerBinding,
  normalizeRestoredMediaObjectKeys,
  normalizeRestoredObjectKeys,
  restoredObjectKeysMissingDurableUrls,
} from "./restoredMediaValidation.ts";

const userId = "00000000-0000-0000-0000-000000000001";

function assertInvalidKeys(value: unknown): void {
  const error = assertThrows(
    () => normalizeRestoredObjectKeys(value, userId),
    PublicHttpError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "invalid_request");
}

function assertInvalidMediaKeySet(
  body: Record<string, unknown>,
): void {
  const error = assertThrows(
    () => normalizeRestoredMediaObjectKeys(body, userId),
    PublicHttpError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "invalid_request");
}

Deno.test("restored media keys are trimmed, deduplicated, and owner scoped", () => {
  assertEquals(
    normalizeRestoredObjectKeys([
      ` staging/${userId}/image-1.webp `,
      `staging/${userId}/image-1.webp`,
      `staging/${userId}/image-2.webp`,
    ], userId.toUpperCase()),
    [
      `staging/${userId}/image-1.webp`,
      `staging/${userId}/image-2.webp`,
    ],
  );
});

Deno.test("restored media keys reject path traversal", () => {
  assertInvalidKeys([`staging/${userId}/../image.webp`]);
});

Deno.test("restored media keys reject nested or empty object names", () => {
  assertInvalidKeys([`staging/${userId}/scan/image.webp`]);
  assertInvalidKeys([`staging/${userId}/`]);
});

Deno.test("restored media keys reject another account", () => {
  assertInvalidKeys([
    "staging/00000000-0000-0000-0000-000000000002/image.webp",
  ]);
});

Deno.test("restored media keys reject non-array and non-string inputs", () => {
  assertInvalidKeys(`staging/${userId}/image.webp`);
  assertInvalidKeys([123]);
});

Deno.test("restored media keys enforce the route media budget", () => {
  assertInvalidKeys([
    `staging/${userId}/1.webp`,
    `staging/${userId}/2.webp`,
    `staging/${userId}/3.webp`,
    `staging/${userId}/4.webp`,
    `staging/${userId}/5.webp`,
    `staging/${userId}/6.webp`,
  ]);
});

Deno.test("restored media key sets enforce canonical kind and aggregate budgets", () => {
  const imageKeys = Array.from(
    { length: 3 },
    (_, index) => `staging/${userId}/image-${index}.webp`,
  );
  assertEquals(
    normalizeRestoredMediaObjectKeys({
      restored_object_keys: imageKeys,
      restored_video_object_keys: [`staging/${userId}/video.mp4`],
      restored_audio_object_keys: [
        `staging/${userId}/audio-1.wav`,
        `staging/${userId}/audio-2.wav`,
      ],
    }, userId),
    {
      restoredObjectKeys: imageKeys,
      restoredVideoObjectKeys: [`staging/${userId}/video.mp4`],
      restoredAudioObjectKeys: [
        `staging/${userId}/audio-1.wav`,
        `staging/${userId}/audio-2.wav`,
      ],
    },
  );

  assertInvalidMediaKeySet({
    restored_video_object_keys: [
      `staging/${userId}/video-1.mp4`,
      `staging/${userId}/video-2.mp4`,
    ],
  });
  assertInvalidMediaKeySet({
    restored_audio_object_keys: [
      `staging/${userId}/audio-1.wav`,
      `staging/${userId}/audio-2.wav`,
      `staging/${userId}/audio-3.wav`,
    ],
  });
  assertInvalidMediaKeySet({
    restored_object_keys: Array.from(
      { length: 5 },
      (_, index) => `staging/${userId}/image-${index}.webp`,
    ),
    restored_audio_object_keys: [
      `staging/${userId}/audio-1.wav`,
      `staging/${userId}/audio-2.wav`,
    ],
  });
});

Deno.test("restored media key sets reject cross-kind key aliases", () => {
  const sharedKey = `staging/${userId}/shared.mp4`;
  assertInvalidMediaKeySet({
    restored_object_keys: [sharedKey],
    restored_video_object_keys: [sharedKey],
  });
});

Deno.test("restored media ledger binds every current key to its scan, kind, and role", () => {
  const imageKey = `staging/${userId}/image.webp`;
  const videoKey = `staging/${userId}/video.mp4`;
  const audioKey = `staging/${userId}/audio.wav`;
  assertRestoredMediaLedgerBinding(
    "10000000-0000-4000-8000-000000000001",
    {
      restoredObjectKeys: [imageKey],
      restoredVideoObjectKeys: [videoKey],
      restoredAudioObjectKeys: [audioKey],
    },
    [
      {
        client_scan_id: "10000000-0000-4000-8000-000000000001",
        kind: "image",
        role: "display",
        storage_key: imageKey,
      },
      {
        client_scan_id: "10000000-0000-4000-8000-000000000001",
        kind: "video",
        role: "playback",
        storage_key: videoKey,
      },
      {
        client_scan_id: "10000000-0000-4000-8000-000000000001",
        kind: "audio",
        role: "audio",
        storage_key: audioKey,
      },
    ],
  );
});

Deno.test("restored media ledger rejects cross-scan, relabeled, and wrong-role keys", () => {
  const scanId = "10000000-0000-4000-8000-000000000001";
  const imageKey = `staging/${userId}/${scanId}_explore_restore_0.webp`;
  for (
    const row of [
      {
        client_scan_id: "20000000-0000-4000-8000-000000000002",
        kind: "image",
        role: "display",
        storage_key: imageKey,
      },
      {
        client_scan_id: scanId,
        kind: "audio",
        role: "audio",
        storage_key: imageKey,
      },
      {
        client_scan_id: scanId,
        kind: "image",
        role: "inference_frame",
        storage_key: imageKey,
      },
    ]
  ) {
    assertThrows(
      () =>
        assertRestoredMediaLedgerBinding(
          scanId,
          {
            restoredObjectKeys: [imageKey],
            restoredVideoObjectKeys: [],
            restoredAudioObjectKeys: [],
          },
          [row],
        ),
      PublicHttpError,
    );
  }
});

Deno.test("restored media ledger rejects a conflicting row beside an exact binding", () => {
  const scanId = "10000000-0000-4000-8000-000000000001";
  const imageKey = `staging/${userId}/${scanId}_explore_restore_0.webp`;
  assertThrows(
    () =>
      assertRestoredMediaLedgerBinding(
        scanId,
        {
          restoredObjectKeys: [imageKey],
          restoredVideoObjectKeys: [],
          restoredAudioObjectKeys: [],
        },
        [
          {
            client_scan_id: scanId,
            kind: "image",
            role: "display",
            storage_key: imageKey,
          },
          {
            client_scan_id: "20000000-0000-4000-8000-000000000002",
            kind: "image",
            role: "display",
            storage_key: imageKey,
          },
        ],
      ),
    PublicHttpError,
  );
});

Deno.test("legacy restored media is limited to its exact scan, category, and inferred kind", () => {
  const scanId = "10000000-0000-4000-8000-000000000001";
  assertRestoredMediaLedgerBinding(
    scanId.toUpperCase(),
    {
      restoredObjectKeys: [
        `staging/${userId}/${scanId}_explore_restore_live.webp`,
        `staging/${userId}/${scanId}_explore_restore_0.heic`,
      ],
      restoredVideoObjectKeys: [
        `staging/${userId}/${scanId}_explore_restore_video_0.mp4`,
      ],
      restoredAudioObjectKeys: [
        `staging/${userId}/${scanId}_explore_restore_audio_0.m4a`,
      ],
    },
    [],
  );

  for (
    const invalidKeys of [
      {
        restoredObjectKeys: [
          `staging/${userId}/20000000-0000-4000-8000-000000000002_explore_restore_0.webp`,
        ],
        restoredVideoObjectKeys: [],
        restoredAudioObjectKeys: [],
      },
      {
        restoredObjectKeys: [
          `staging/${userId}/${scanId}_explore_restore_video_0.webp`,
        ],
        restoredVideoObjectKeys: [],
        restoredAudioObjectKeys: [],
      },
      {
        restoredObjectKeys: [
          `staging/${userId}/${scanId}_explore_restore_0.mp4`,
        ],
        restoredVideoObjectKeys: [],
        restoredAudioObjectKeys: [],
      },
      {
        restoredObjectKeys: [],
        restoredVideoObjectKeys: [
          `staging/${userId}/${scanId}_explore_restore_video_0.wav`,
        ],
        restoredAudioObjectKeys: [],
      },
    ]
  ) {
    assertThrows(
      () => assertRestoredMediaLedgerBinding(scanId, invalidKeys, []),
      PublicHttpError,
    );
  }
});

Deno.test("restored media retry skips only its exact canonical durable owner URL", () => {
  const firstKey = `staging/${userId}/audio-1.wav`;
  const secondKey = `staging/${userId}/audio-2.wav`;
  assertEquals(
    restoredObjectKeysMissingDurableUrls(
      [firstKey, secondKey],
      [
        `https://media.merian.app/public_uploads/pro/${userId}/audio-1.wav`,
        "https://media.merian.app/public_uploads/pro/00000000-0000-0000-0000-000000000002/audio-2.wav",
        `https://other.example/public_uploads/pro/${userId}/audio-2.wav`,
      ],
      userId,
    ),
    [secondKey],
  );
});
