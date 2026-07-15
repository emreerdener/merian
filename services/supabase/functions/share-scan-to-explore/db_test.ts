import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildExplorePostMediaRows } from "../_shared/explorePostMedia.ts";
import {
  attachAudioSpectrogramThumbnails,
  buildRestoredAudioCapturedMedia,
  buildRestoredVideoCapturedMedia,
} from "./db.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  SelectedExplorePostMediaItem,
  ShareEligibleScanRow,
} from "./db.ts";

const scanId = "00000000-0000-0000-0000-000000000001";

function makeVideoScan(
  capturedMedia: unknown[],
  imageStorageUrls: string[] = [],
): ShareEligibleScanRow {
  return {
    id: scanId,
    user_id: "00000000-0000-0000-0000-000000000002",
    geoprivacy: "open",
    image_storage_urls: imageStorageUrls,
    video_storage_urls: ["https://media.merian.app/clip.mp4"],
    captured_media: capturedMedia,
    is_tombstoned: false,
    species_id: "00000000-0000-0000-0000-000000000003",
    confirmed_species_id: null,
  };
}

Deno.test("buildExplorePostMediaRows resolves selected manifest videos by source_media_id", () => {
  const scan = makeVideoScan([
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
  ]);
  const selection: SelectedExplorePostMediaItem[] = [
    {
      kind: "video",
      source_media_id: `scan:${scanId}:video:0`,
      order_index: 0,
    },
  ];

  assertEquals(buildExplorePostMediaRows(scan, selection), [
    {
      kind: "video",
      url: "https://media.merian.app/clip.mp4",
      thumbnail_url: "https://media.merian.app/poster.webp",
      order_index: 0,
      duration_seconds: null,
      has_audio: false,
    },
  ]);
});

Deno.test("buildExplorePostMediaRows marks manifest video audio only when audio reference exists", () => {
  const scan = makeVideoScan([
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
          audio: {
            storage: "remoteURL",
            path: "https://media.merian.app/clip-audio.wav",
          },
        },
      },
    },
  ]);

  assertEquals(buildExplorePostMediaRows(scan, undefined), [
    {
      kind: "video",
      url: "https://media.merian.app/clip.mp4",
      thumbnail_url: "https://media.merian.app/poster.webp",
      order_index: 0,
      duration_seconds: null,
      has_audio: true,
    },
  ]);
});

Deno.test("buildExplorePostMediaRows rejects manifest videos without poster thumbnails", () => {
  const scan = makeVideoScan([
    {
      video: {
        _0: {
          video: {
            storage: "remoteURL",
            path: "https://media.merian.app/clip.mp4",
          },
        },
      },
    },
  ]);

  const error = assertThrows(() => buildExplorePostMediaRows(scan, undefined));
  if (!(error instanceof Error)) {
    throw new Error("Expected an Error.");
  }
  assertEquals(error.message, "Video thumbnail unavailable.");
});

Deno.test("buildRestoredVideoCapturedMedia collapses frame-only video rows into one video item", () => {
  const imageUrls = [0, 1, 2, 3, 4].map((index) =>
    `https://media.merian.app/frame-${index}.webp`
  );
  const scan: ShareEligibleScanRow = {
    id: scanId,
    user_id: "00000000-0000-0000-0000-000000000002",
    geoprivacy: "open",
    image_storage_urls: imageUrls,
    video_storage_urls: [],
    captured_media: imageUrls.map((url) => ({
      image: {
        _0: {
          storage: "remoteURL",
          path: url,
        },
      },
    })),
    is_tombstoned: false,
    species_id: "00000000-0000-0000-0000-000000000003",
    confirmed_species_id: null,
  };

  assertEquals(
    buildRestoredVideoCapturedMedia(scan, [
      "https://media.merian.app/clip.mp4",
    ]),
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
              path: "https://media.merian.app/frame-0.webp",
            },
          },
        },
      },
    ],
  );
});

Deno.test("buildRestoredAudioCapturedMedia replaces local legacy audio with durable references", () => {
  const scan = makeVideoScan([
    { audio: { _0: { storage: "localFile", path: "legacy.wav" } } },
    {
      image: {
        _0: {
          storage: "remoteURL",
          path: "https://media.merian.app/image.webp",
        },
      },
    },
  ]);
  assertEquals(
    buildRestoredAudioCapturedMedia(scan, [
      "https://media.merian.app/restored.wav",
    ]),
    [
      {
        image: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/image.webp",
          },
        },
      },
      {
        audio: {
          _0: {
            storage: "remoteURL",
            path: "https://media.merian.app/restored.wav",
          },
        },
      },
    ],
  );
});

Deno.test("video restoration preserves already-restored standalone audio", () => {
  const imageUrls = [0, 1, 2, 3, 4].map((index) =>
    `https://media.merian.app/frame-${index}.webp`
  );
  const audioItem = {
    audio: {
      _0: {
        storage: "remoteURL",
        path: "https://media.merian.app/restored.wav",
      },
    },
  };
  const scan = makeVideoScan([
    ...imageUrls.map((url) => ({
      image: { _0: { storage: "remoteURL", path: url } },
    })),
    audioItem,
  ], imageUrls);
  scan.video_storage_urls = [];
  assertEquals(
    buildRestoredVideoCapturedMedia(scan, [
      "https://media.merian.app/clip.mp4",
    ]),
    [
      {
        video: {
          _0: {
            video: {
              storage: "remoteURL",
              path: "https://media.merian.app/clip.mp4",
            },
            thumbnail: { storage: "remoteURL", path: imageUrls[0] },
          },
        },
      },
      audioItem,
    ],
  );
});

Deno.test("attachAudioSpectrogramThumbnails snapshots and persists generated audio posters", async () => {
  const updates: Array<Record<string, unknown>> = [];
  const query = {
    error: null,
    eq() {
      return this;
    },
  };
  const supabase = {
    from(table: string) {
      assertEquals(table, "scan_media_assets");
      return {
        update(values: Record<string, unknown>) {
          updates.push(values);
          return query;
        },
      };
    },
  } as unknown as SupabaseClient;
  const rows = [{
    kind: "audio" as const,
    url: "https://media.merian.app/public_uploads/pro/user/clip.wav",
    thumbnail_url: "",
    order_index: 0,
    duration_seconds: null,
    has_audio: true,
  }];

  const result = await attachAudioSpectrogramThumbnails(
    scanId,
    rows,
    supabase,
    () =>
      Promise.resolve(
        "https://media.merian.app/public_uploads/pro/user/spectrogram.png",
      ),
  );

  assertEquals(
    result[0].thumbnail_url,
    "https://media.merian.app/public_uploads/pro/user/spectrogram.png",
  );
  assertEquals(updates, [{
    thumbnail_url:
      "https://media.merian.app/public_uploads/pro/user/spectrogram.png",
  }]);
});
