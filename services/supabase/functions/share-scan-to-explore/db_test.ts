import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildExplorePostMediaRows } from "../_shared/explorePostMedia.ts";
import { PublicHttpError } from "../_shared/http.ts";
import {
  attachAudioSpectrogramThumbnails,
  buildRestoredAudioCapturedMedia,
  buildRestoredVideoCapturedMedia,
  fetchShareEligibleScan,
  publishExplorePostAtomically,
  resolveRestoredMediaPersistence,
  restoredMediaPersistenceAllowsRollback,
  scanContainsDurableMediaUrls,
} from "./db.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  SelectedExplorePostMediaItem,
  ShareEligibleScanRow,
} from "./db.ts";
import type { OwnedScanRecoveryRow } from "../_shared/scanRecovery.ts";

const scanId = "00000000-0000-0000-0000-000000000001";
const userId = "00000000-0000-0000-0000-000000000002";

const unusedModerationQuota = {
  beforeProvider() {
    throw new Error("Image-only publication must not reserve audio moderation");
  },
};

function restorationScan(
  overrides: Partial<ShareEligibleScanRow> = {},
): ShareEligibleScanRow {
  return {
    id: scanId,
    user_id: userId,
    geoprivacy: "open",
    image_storage_urls: [],
    video_storage_urls: [],
    audio_storage_urls: [],
    captured_media: null,
    is_tombstoned: false,
    species_id: "00000000-0000-0000-0000-000000000003",
    confirmed_species_id: null,
    ...overrides,
  };
}

function restorationReadClient(
  result:
    | { data: ShareEligibleScanRow | null; error: { message: string } | null }
    | Error,
): SupabaseClient {
  const filters = new Map<string, unknown>();
  return {
    from(table: string) {
      assertEquals(table, "scans");
      return {
        select() {
          const query = {
            eq(column: string, value: unknown) {
              filters.set(column, value);
              return query;
            },
            maybeSingle() {
              assertEquals(filters.get("id"), scanId);
              assertEquals(filters.get("user_id"), userId);
              if (result instanceof Error) return Promise.reject(result);
              return Promise.resolve(result);
            },
          };
          return query;
        },
      };
    },
  } as unknown as SupabaseClient;
}

Deno.test("scanContainsDurableMediaUrls requires every exact restored URL", () => {
  const row = restorationScan({
    audio_storage_urls: [
      "https://media.merian.app/public_uploads/pro/user/one.wav",
      " https://media.merian.app/public_uploads/pro/user/two.wav ",
    ],
  });
  assertEquals(
    scanContainsDurableMediaUrls(row, "audio_storage_urls", [
      "https://media.merian.app/public_uploads/pro/user/one.wav",
      "https://media.merian.app/public_uploads/pro/user/two.wav",
    ]),
    true,
  );
  assertEquals(
    scanContainsDurableMediaUrls(row, "audio_storage_urls", [
      "https://media.merian.app/public_uploads/pro/user/missing.wav",
    ]),
    false,
  );
});

Deno.test("Explore publication sends one complete transactional RPC", async () => {
  const imageUrl = "https://media.merian.app/public_uploads/free/user/one.webp";
  const calls: Array<{ name: string; arguments_: unknown }> = [];
  const supabase = {
    rpc(name: string, arguments_: unknown) {
      calls.push({ name, arguments_ });
      return Promise.resolve({
        data: {
          post_id: "00000000-0000-4000-8000-000000000010",
          shared_at: "2026-07-29T02:45:00Z",
          location_sharing: "obscured",
          publication_status: "published",
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;
  const scan = restorationScan({ image_storage_urls: [imageUrl] });

  const result = await publishExplorePostAtomically(
    scan,
    userId,
    "Monarch",
    "Observed on milkweed.",
    null,
    undefined,
    ["pollinators"],
    supabase,
    unusedModerationQuota,
  );

  assertEquals(calls, [{
    name: "publish_scan_to_explore_atomically",
    arguments_: {
      p_scan_id: scanId,
      p_user_id: userId,
      p_species_common_name: "Monarch",
      p_field_notes: "Observed on milkweed.",
      p_location_sharing: null,
      p_media_rows: [{
        kind: "image",
        url: imageUrl,
        thumbnail_url: imageUrl,
        order_index: 0,
        duration_seconds: null,
        has_audio: false,
      }],
      p_hashtags: ["pollinators"],
    },
  }]);
  assertEquals(result.id, "00000000-0000-4000-8000-000000000010");
  assertEquals(result.location_sharing, "obscured");
  assertEquals(result.publication_status, "published");
});

Deno.test("Explore publication rejects an unconfirmed transactional response", async () => {
  const imageUrl = "https://media.merian.app/public_uploads/free/user/one.webp";
  const supabase = {
    rpc() {
      return Promise.resolve({
        data: {
          post_id: "00000000-0000-4000-8000-000000000010",
          shared_at: "2026-07-29T02:45:00Z",
          location_sharing: "private",
          publication_status: "draft",
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      publishExplorePostAtomically(
        restorationScan({ image_storage_urls: [imageUrl] }),
        userId,
        null,
        null,
        "private",
        undefined,
        [],
        supabase,
        unusedModerationQuota,
      ),
    Error,
    "Failed to publish scan to Explore atomically: Invalid database response",
  );
});

Deno.test("Explore publication rejects an invalid transactional timestamp", async () => {
  const imageUrl = "https://media.merian.app/public_uploads/free/user/one.webp";
  const supabase = {
    rpc() {
      return Promise.resolve({
        data: {
          post_id: "00000000-0000-4000-8000-000000000010",
          shared_at: "not-a-timestamp",
          location_sharing: "private",
          publication_status: "published",
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      publishExplorePostAtomically(
        restorationScan({ image_storage_urls: [imageUrl] }),
        userId,
        null,
        null,
        "private",
        undefined,
        [],
        supabase,
        unusedModerationQuota,
      ),
    Error,
    "Failed to publish scan to Explore atomically: Invalid database response",
  );
});

Deno.test("Explore publication maps a transaction-time pending community request to conflict", async () => {
  const imageUrl = "https://media.merian.app/public_uploads/free/user/one.webp";
  const message =
    "Wait for the community to identify this request before sharing it to Explore.";
  const supabase = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: { code: "P0001", message },
      });
    },
  } as unknown as SupabaseClient;

  const error = await assertRejects(
    () =>
      publishExplorePostAtomically(
        restorationScan({ image_storage_urls: [imageUrl] }),
        userId,
        null,
        null,
        "private",
        undefined,
        [],
        supabase,
        unusedModerationQuota,
      ),
    PublicHttpError,
    message,
  );
  assertEquals((error as PublicHttpError).status, 409);
});

Deno.test("Explore publication does not map an unrelated error with matching text to conflict", async () => {
  const imageUrl = "https://media.merian.app/public_uploads/free/user/one.webp";
  const message =
    "Wait for the community to identify this request before sharing it to Explore.";
  const supabase = {
    rpc() {
      return Promise.resolve({
        data: null,
        error: { code: "42501", message },
      });
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      publishExplorePostAtomically(
        restorationScan({ image_storage_urls: [imageUrl] }),
        userId,
        null,
        null,
        "private",
        undefined,
        [],
        supabase,
        unusedModerationQuota,
      ),
    Error,
    `Failed to publish scan to Explore atomically: ${message}`,
  );
});

Deno.test("restored-media persistence accepts an exact direct update response without rereading", async () => {
  const expectedUrl = "https://media.merian.app/restored.webp";
  const row = restorationScan({ image_storage_urls: [expectedUrl] });
  const neverRead = {
    from() {
      throw new Error("directly confirmed updates must not reread");
    },
  } as unknown as SupabaseClient;

  const resolution = await resolveRestoredMediaPersistence(
    row,
    "reported_success",
    "image_storage_urls",
    [expectedUrl],
    scanId,
    userId,
    neverRead,
  );
  assertEquals(resolution.outcome, "committed");
});

Deno.test("restored-media persistence reconciles a returned update error when the owner row committed", async () => {
  const expectedUrl = "https://media.merian.app/restored.mp4";
  const row = restorationScan({ video_storage_urls: [expectedUrl] });
  const resolution = await resolveRestoredMediaPersistence(
    null,
    "reported_rejected",
    "video_storage_urls",
    [expectedUrl],
    scanId,
    userId,
    restorationReadClient({ data: row, error: null }),
    "PostgREST response error",
  );
  assertEquals(resolution.outcome, "committed");
});

Deno.test("restored-media cleanup is allowed only after a returned rejection and a definitive absent reread", async () => {
  const resolution = await resolveRestoredMediaPersistence(
    null,
    "reported_rejected",
    "image_storage_urls",
    ["https://media.merian.app/restored.webp"],
    scanId,
    userId,
    restorationReadClient({ data: restorationScan(), error: null }),
    "constraint rejected",
  );
  assertEquals(resolution, {
    outcome: "rejected",
    row: null,
    reason: "constraint rejected",
  });
});

Deno.test("restored-media persistence stays unknown after a lost update response and an absent reread", async () => {
  const resolution = await resolveRestoredMediaPersistence(
    null,
    "unknown",
    "audio_storage_urls",
    ["https://media.merian.app/restored.wav"],
    scanId,
    userId,
    restorationReadClient({ data: restorationScan(), error: null }),
    "network timeout",
  );
  assertEquals(resolution, {
    outcome: "unknown",
    row: null,
    reason: "network timeout",
  });
});

Deno.test("restored-media persistence preserves objects when exact-owner verification fails", async () => {
  const resolution = await resolveRestoredMediaPersistence(
    null,
    "reported_success",
    "audio_storage_urls",
    ["https://media.merian.app/restored.wav"],
    scanId,
    userId,
    restorationReadClient({
      data: null,
      error: { message: "read unavailable" },
    }),
  );
  assertEquals(resolution.outcome, "unknown");
  assertEquals(
    resolution.reason,
    "Failed to load scan for Explore sharing: read unavailable",
  );
});

Deno.test("restored-media rollback is forbidden for every outcome except a proven rejection", () => {
  assertEquals(
    restoredMediaPersistenceAllowsRollback({
      outcome: "unknown",
      row: null,
      reason: "lost response",
    }),
    false,
  );
  assertEquals(
    restoredMediaPersistenceAllowsRollback({
      outcome: "rejected",
      row: null,
      reason: "database rejected update",
    }),
    true,
  );
  assertEquals(
    restoredMediaPersistenceAllowsRollback({
      outcome: "committed",
      row: restorationScan(),
      reason: "owner row verified",
    }),
    false,
  );
});

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

Deno.test("fetchShareEligibleScan distinguishes a database failure from a missing scan", async () => {
  const query = {
    select() {
      return this;
    },
    eq() {
      return this;
    },
    maybeSingle() {
      return Promise.resolve({
        data: null,
        error: { message: "permission denied for table scans" },
      });
    },
  };
  const supabase = {
    from(table: string) {
      assertEquals(table, "scans");
      return query;
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      fetchShareEligibleScan(
        scanId,
        "00000000-0000-0000-0000-000000000002",
        [],
        [],
        [],
        supabase,
      ),
    Error,
    "Failed to load scan for Explore sharing: permission denied for table scans",
  );
});

Deno.test("fetchShareEligibleScan returns a 404 only for an absent scan", async () => {
  const query = {
    select() {
      return this;
    },
    eq() {
      return this;
    },
    maybeSingle() {
      return Promise.resolve({ data: null, error: null });
    },
  };
  const supabase = {
    from() {
      return query;
    },
  } as unknown as SupabaseClient;

  const error = await assertRejects(() =>
    fetchShareEligibleScan(
      scanId,
      "00000000-0000-0000-0000-000000000002",
      [],
      [],
      [],
      supabase,
    )
  );
  assertEquals(error instanceof PublicHttpError, true);
  assertEquals((error as PublicHttpError).status, 404);
});

Deno.test("fetchShareEligibleScan maps recovery-boundary failures to retryable 503", async () => {
  let reads = 0;
  const rpcCalls: string[] = [];
  const supabase = {
    rpc(name: string) {
      rpcCalls.push(name);
      return Promise.resolve({
        data: null,
        error: { message: "proof RPC is not visible" },
      });
    },
    from(table: string) {
      assertEquals(table, "scans");
      return {
        select() {
          return {
            eq() {
              return this;
            },
            maybeSingle() {
              reads += 1;
              return Promise.resolve({ data: null, error: null });
            },
          };
        },
      };
    },
  } as unknown as SupabaseClient;
  const recoveryScan = {
    id: scanId,
    user_id: userId,
  } as OwnedScanRecoveryRow;

  const error = await assertRejects(() =>
    fetchShareEligibleScan(
      scanId,
      userId,
      [],
      [],
      [],
      supabase,
      recoveryScan,
    )
  );

  assertEquals(error instanceof PublicHttpError, true);
  assertEquals((error as PublicHttpError).status, 503);
  assertEquals((error as PublicHttpError).code, "service_unavailable");
  assertEquals((error as PublicHttpError).retryAfterSeconds, 30);
  assertEquals(reads, 1);
  assertEquals(rpcCalls, ["get_media_abandoned_scan_recovery_proofs"]);
});

Deno.test("fetchShareEligibleScan recreates a missing owner scan before sharing", async () => {
  const userId = "00000000-0000-0000-0000-000000000002";
  const recoveredRow: ShareEligibleScanRow = {
    id: scanId,
    user_id: userId,
    geoprivacy: "private",
    image_storage_urls: ["https://media.merian.app/recovered.webp"],
    video_storage_urls: [],
    audio_storage_urls: [],
    captured_media: null,
    is_tombstoned: false,
    species_id: "00000000-0000-0000-0000-000000000003",
    confirmed_species_id: null,
  };
  const reads = [
    { data: null, error: null },
    { data: recoveredRow, error: null },
  ];
  const rpcCalls: Array<{ name: string; arguments_: unknown }> = [];
  const supabase = {
    rpc(name: string, arguments_: unknown) {
      rpcCalls.push({ name, arguments_ });
      if (name === "get_media_abandoned_scan_recovery_proofs") {
        return Promise.resolve({ data: [], error: null });
      }
      if (name === "recover_missing_owned_scan") {
        return Promise.resolve({ data: "recovered", error: null });
      }
      throw new Error(`Unexpected RPC: ${name}`);
    },
    from(table: string) {
      assertEquals(table, "scans");
      return {
        select() {
          return {
            eq() {
              return this;
            },
            maybeSingle() {
              return Promise.resolve(reads.shift());
            },
          };
        },
      };
    },
  } as unknown as SupabaseClient;
  const recoveryScan = {
    id: scanId,
    user_id: userId,
  } as OwnedScanRecoveryRow;

  const result = await fetchShareEligibleScan(
    scanId,
    userId,
    [],
    [],
    [],
    supabase,
    recoveryScan,
  );

  assertEquals(result, recoveredRow);
  assertEquals(rpcCalls, [
    {
      name: "get_media_abandoned_scan_recovery_proofs",
      arguments_: {
        p_user_id: userId,
        p_scan_ids: [scanId],
      },
    },
    {
      name: "recover_missing_owned_scan",
      arguments_: {
        p_scan_id: scanId,
        p_user_id: userId,
        p_recovery_scan: recoveryScan,
      },
    },
  ]);
});
