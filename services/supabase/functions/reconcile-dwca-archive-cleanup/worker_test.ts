import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  classifyDwcaArchiveCleanupHealth,
  DwcaArchiveCleanupServices,
  reconcileDwcaArchiveCleanup,
} from "./worker.ts";

const unusedClient = {} as SupabaseClient;
const generatedAt = "2026-07-28T04:00:00.000Z";
const healthy = {
  generatedAt,
  pendingCount: 0,
  processingCount: 0,
  expiredLeaseCount: 0,
  oldestDueAt: null,
  oldestDueAgeSeconds: null,
};

Deno.test("cleanup drains multiple claim waves and completes idempotent deletes", async () => {
  const events: string[] = [];
  let wave = 0;
  const result = await reconcileDwcaArchiveCleanup(
    unusedClient,
    {
      claim(token, limit) {
        assertStringIncludes(token, "-");
        assertEquals(limit, 25);
        wave += 1;
        if (wave > 2) return Promise.resolve([]);
        return Promise.resolve([{
          cleanupId: `00000000-0000-4000-8000-00000000010${wave}`,
          jobId: `00000000-0000-4000-8000-00000000020${wave}`,
          objectKey:
            `exports/00000000-0000-4000-8000-000000000301/00000000-0000-4000-8000-00000000020${wave}/00000000-0000-4000-8000-00000000040${wave}.zip`,
          attemptCount: 1,
        }]);
      },
      deleteObject(key) {
        events.push(`delete:${key}`);
        return Promise.resolve();
      },
      complete(id) {
        events.push(`complete:${id}`);
        return Promise.resolve();
      },
      release() {
        throw new Error("unexpected release");
      },
      health: () => Promise.resolve(healthy),
      now: () => 1_000,
    },
  );

  assertEquals(result.claimed, 2);
  assertEquals(result.completed, 2);
  assertEquals(result.deferred, 0);
  assertEquals(result.healthStatus, "healthy");
  assertEquals(events.filter((event) => event.startsWith("delete:")).length, 2);
  assertEquals(
    events.filter((event) => event.startsWith("complete:")).length,
    2,
  );
});

Deno.test("failed deletes are durably released with a stable error code", async () => {
  const events: string[] = [];
  let claimed = false;
  const result = await reconcileDwcaArchiveCleanup(
    unusedClient,
    {
      claim() {
        if (claimed) return Promise.resolve([]);
        claimed = true;
        return Promise.resolve([{
          cleanupId: "00000000-0000-4000-8000-000000000101",
          jobId: null,
          objectKey:
            "exports/00000000-0000-4000-8000-000000000301/00000000-0000-4000-8000-000000000201/00000000-0000-4000-8000-000000000401.zip",
          attemptCount: 3,
        }]);
      },
      deleteObject: () => Promise.reject(new Error("R2 internals")),
      complete() {
        throw new Error("unexpected completion");
      },
      release(id, _token, code) {
        events.push(`${id}:${code}`);
        return Promise.resolve();
      },
      health: () => Promise.resolve(healthy),
      now: () => 1_000,
    },
  );

  assertEquals(result.deferred, 1);
  assertEquals(events, [
    "00000000-0000-4000-8000-000000000101:archive_delete_failed",
  ]);
});

Deno.test("cleanup health thresholds independently flag stuck work", () => {
  assertEquals(classifyDwcaArchiveCleanupHealth(healthy), "healthy");
  assertEquals(
    classifyDwcaArchiveCleanupHealth({
      ...healthy,
      pendingCount: 25,
      oldestDueAt: generatedAt,
      oldestDueAgeSeconds: 900,
    }),
    "warning",
  );
  assertEquals(
    classifyDwcaArchiveCleanupHealth({
      ...healthy,
      expiredLeaseCount: 1,
    }),
    "critical",
  );
  assertEquals(
    classifyDwcaArchiveCleanupHealth({
      ...healthy,
      pendingCount: 100,
    }),
    "critical",
  );
});

Deno.test("cleanup stops claiming after its runtime deadline", async () => {
  let now = 1_000;
  let claims = 0;
  const job = {
    cleanupId: "00000000-0000-4000-8000-000000000101",
    jobId: null,
    objectKey:
      "exports/00000000-0000-4000-8000-000000000301/00000000-0000-4000-8000-000000000201/00000000-0000-4000-8000-000000000401.zip",
    attemptCount: 1,
  };
  const result = await reconcileDwcaArchiveCleanup(
    unusedClient,
    {
      claim() {
        claims += 1;
        return Promise.resolve([job]);
      },
      deleteObject() {
        now += 40_000;
        return Promise.resolve();
      },
      complete: () => Promise.resolve(),
      release: () => Promise.resolve(),
      health: () => Promise.resolve(healthy),
      now: () => now,
    } satisfies Partial<DwcaArchiveCleanupServices>,
  );
  assertEquals(claims, 1);
  assertEquals(result.runtimeDeadlineReached, true);
});
