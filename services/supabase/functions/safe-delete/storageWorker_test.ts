import { assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { R2Config } from "../_shared/aws.ts";
import type { StorageDeletionClaim } from "./storageDb.ts";
import { processPendingStorageDeletions } from "./storageWorker.ts";

const claim: StorageDeletionClaim = {
  deletionId: "00000000-0000-4000-8000-000000000501",
  targetUserId: "00000000-0000-4000-8000-000000000502",
  objectPrefix: "public_uploads/free/00000000-0000-4000-8000-000000000502/",
  startAfterKey: null,
  phase: "verification",
  claimToken: "00000000-0000-4000-8000-000000000503",
  claimExpiresAt: "2026-07-25T06:00:00.000Z",
};

const fakeConfig = {} as R2Config;
const fakeSupabase = {} as SupabaseClient;

Deno.test("storage eraser deletes one bounded page before terminal advancement", async () => {
  const deleted: string[] = [];
  let advancedWith: {
    lastKey: string | null;
    prefixFinished: boolean;
  } | null = null;

  const result = await processPendingStorageDeletions(
    fakeSupabase,
    1,
    {
      claim: () => Promise.resolve([claim]),
      config: () => fakeConfig,
      list: () =>
        Promise.resolve({
          keys: [`${claim.objectPrefix}a.webp`, `${claim.objectPrefix}b.webp`],
          isTruncated: false,
        }),
      delete: (key) => {
        deleted.push(key);
        return Promise.resolve(new Response(null, { status: 204 }));
      },
      advance: (_admin, _claim, lastKey, prefixFinished) => {
        advancedWith = { lastKey, prefixFinished };
        return Promise.resolve("completed");
      },
    },
  );

  assertEquals(deleted.sort(), [
    `${claim.objectPrefix}a.webp`,
    `${claim.objectPrefix}b.webp`,
  ]);
  assertEquals(advancedWith, {
    lastKey: `${claim.objectPrefix}b.webp`,
    prefixFinished: true,
  });
  assertEquals(result, {
    claimed: 1,
    completed: 1,
    advanced: 1,
    deferred: 0,
    failures: [],
  });
});

Deno.test("storage eraser releases the lease after a provider failure", async () => {
  let failureCode = "";
  const result = await processPendingStorageDeletions(
    fakeSupabase,
    1,
    {
      claim: () => Promise.resolve([claim]),
      config: () => fakeConfig,
      list: () =>
        Promise.resolve({
          keys: [`${claim.objectPrefix}a.webp`],
          isTruncated: false,
        }),
      delete: () => Promise.resolve(new Response(null, { status: 503 })),
      advance: () => {
        throw new Error("advance must not run after a delete failure");
      },
      fail: (_admin, _claim, code) => {
        failureCode = code;
        return Promise.resolve();
      },
    },
  );

  assertEquals(failureCode, "r2_erasure_failed");
  assertEquals(result.deferred, 1);
  assertEquals(result.completed, 0);
});

Deno.test("storage eraser clamps caller work to the Edge wall-clock budget", async () => {
  let claimedLimit = 0;
  await processPendingStorageDeletions(
    fakeSupabase,
    Number.MAX_SAFE_INTEGER,
    {
      claim: (_admin, limit) => {
        claimedLimit = limit;
        return Promise.resolve([]);
      },
      config: () => fakeConfig,
    },
  );

  assertEquals(claimedLimit, 4);
});
