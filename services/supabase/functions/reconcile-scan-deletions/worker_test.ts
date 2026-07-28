import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  classifyScanDeletionHealth,
  reconcileScanDeletions,
  type ScanDeletionReconciliationServices,
} from "./worker.ts";

const unusedClient = {} as SupabaseClient;
const generatedAt = "2026-07-28T06:00:00.000Z";
const healthy = {
  generatedAt,
  pendingCount: 0,
  processingCount: 0,
  expiredLeaseCount: 0,
  oldestPendingAt: null,
  oldestPendingAgeSeconds: null,
};

function claim(sequence: number) {
  return {
    scanId: `00000000-0000-4000-8000-00000000010${sequence}`,
    userId: "00000000-0000-4000-8000-000000000201",
    attemptCount: 1,
  };
}

Deno.test("scan deletion reconciliation drains waves in fenced order", async () => {
  const events: string[] = [];
  let wave = 0;
  const result = await reconcileScanDeletions(unusedClient, {
    claim(token, limit) {
      assertStringIncludes(token, "-");
      assertEquals(limit, 25);
      wave += 1;
      return Promise.resolve(wave <= 2 ? [claim(wave)] : []);
    },
    loadScan(scanId) {
      events.push(`fetch:${scanId}`);
      return Promise.resolve({
        id: scanId,
        user_id: "00000000-0000-4000-8000-000000000201",
        image_storage_urls: ["https://media.example/source.webp"],
        video_storage_urls: [],
        audio_storage_urls: [],
        derived_media_urls: ["https://media.example/thumb.webp"],
      });
    },
    deleteMedia(urls, ownerUserId) {
      events.push(`delete:${ownerUserId}:${urls.join(",")}`);
      return Promise.resolve();
    },
    complete(scanId) {
      events.push(`complete:${scanId}`);
      return Promise.resolve();
    },
    release() {
      throw new Error("unexpected release");
    },
    health: () => Promise.resolve(healthy),
    now: () => 1_000,
  });

  assertEquals(result.claimed, 2);
  assertEquals(result.completed, 2);
  assertEquals(result.deferred, 0);
  assertEquals(result.healthStatus, "healthy");
  for (const job of [claim(1), claim(2)]) {
    const fetchIndex = events.indexOf(`fetch:${job.scanId}`);
    const completeIndex = events.indexOf(`complete:${job.scanId}`);
    assertEquals(fetchIndex >= 0 && completeIndex > fetchIndex, true);
  }
  assertEquals(
    events.filter((event) =>
      event.startsWith(
        "delete:00000000-0000-4000-8000-000000000201:",
      )
    ).length,
    2,
  );
});

Deno.test("scan deletion reconciliation rejects an owner-fence change", async () => {
  const releases: string[] = [];
  let didClaim = false;
  const job = claim(1);
  const result = await reconcileScanDeletions(unusedClient, {
    claim() {
      if (didClaim) return Promise.resolve([]);
      didClaim = true;
      return Promise.resolve([job]);
    },
    loadScan: () =>
      Promise.resolve({
        id: job.scanId,
        user_id: "00000000-0000-4000-8000-000000000999",
        image_storage_urls: [],
        video_storage_urls: [],
        audio_storage_urls: [],
        derived_media_urls: [],
      }),
    deleteMedia() {
      throw new Error("unexpected media deletion");
    },
    complete() {
      throw new Error("unexpected completion");
    },
    release(_scanId, _userId, _token, code) {
      releases.push(code);
      return Promise.resolve();
    },
    health: () => Promise.resolve(healthy),
    now: () => 1_000,
  });

  assertEquals(result.deferred, 1);
  assertEquals(releases, ["scan_deletion_failed"]);
});

Deno.test("scan deletion health independently flags stuck work", () => {
  assertEquals(classifyScanDeletionHealth(healthy), "healthy");
  assertEquals(
    classifyScanDeletionHealth({
      ...healthy,
      pendingCount: 25,
      oldestPendingAt: generatedAt,
      oldestPendingAgeSeconds: 900,
    }),
    "warning",
  );
  assertEquals(
    classifyScanDeletionHealth({
      ...healthy,
      expiredLeaseCount: 1,
    }),
    "critical",
  );
  assertEquals(
    classifyScanDeletionHealth({
      ...healthy,
      oldestPendingAt: generatedAt,
      oldestPendingAgeSeconds: 3600,
    }),
    "critical",
  );
});

Deno.test("scan deletion reconciliation stops at its runtime deadline", async () => {
  let now = 1_000;
  let claims = 0;
  const job = claim(1);
  const result = await reconcileScanDeletions(
    unusedClient,
    {
      claim() {
        claims += 1;
        return Promise.resolve([job]);
      },
      loadScan() {
        now += 40_000;
        return Promise.resolve(null);
      },
      deleteMedia: () => Promise.resolve(),
      complete: () => Promise.resolve(),
      release: () => Promise.resolve(),
      health: () => Promise.resolve(healthy),
      now: () => now,
    } satisfies Partial<ScanDeletionReconciliationServices>,
  );
  assertEquals(claims, 1);
  assertEquals(result.runtimeDeadlineReached, true);
});
