import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildExplorePostMediaRows } from "../_shared/explorePostMedia.ts";
import { buildRestoredVideoCapturedMedia } from "./db.ts";
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
