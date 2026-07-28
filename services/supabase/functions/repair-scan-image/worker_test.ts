import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { R2Config } from "../_shared/aws.ts";
import { PublicHttpError } from "../_shared/http.ts";
import { ScanImageRepairPersistenceOutcomeUnknownError } from "./db.ts";
import { inspectOwnedScanImage, repairOwnedScanImage } from "./worker.ts";

const userId = "4c600000-0000-4000-8000-000000000001";
const sourceUrl =
  `https://media.merian.app/public_uploads/free/${userId}/old.webp`;
const restoredKey = `staging/${userId}/repair_new.webp`;
const replacementUrl =
  `https://media.merian.app/public_uploads/pro/${userId}/repair_new.webp`;
const supabase = {} as SupabaseClient;
const config = {} as R2Config;

Deno.test("scan image inspection distinguishes unreferenced and missing media", async () => {
  let headCalls = 0;
  assertEquals(
    await inspectOwnedScanImage(userId, sourceUrl, supabase, {
      referenceExists: () => Promise.resolve(false),
      headObject: () => {
        headCalls += 1;
        return Promise.resolve(new Response(null, { status: 404 }));
      },
      config: () => config,
    }),
    "not_referenced",
  );
  assertEquals(headCalls, 0);

  assertEquals(
    await inspectOwnedScanImage(userId, sourceUrl, supabase, {
      referenceExists: () => Promise.resolve(true),
      headObject: () => Promise.resolve(new Response(null, { status: 404 })),
      config: () => config,
    }),
    "missing",
  );
});

Deno.test("scan image repair promotes then atomically persists replacement", async () => {
  const headKeys: string[] = [];
  const result = await repairOwnedScanImage(
    userId,
    sourceUrl,
    restoredKey,
    supabase,
    {
      referenceExists: () => Promise.resolve(true),
      headObject: (key) => {
        headKeys.push(key);
        return Promise.resolve(
          new Response(null, {
            status: key === restoredKey ? 200 : 404,
          }),
        );
      },
      tierForUser: () => Promise.resolve("pro"),
      promoteMedia: () => Promise.resolve([replacementUrl]),
      persistRepair: () =>
        Promise.resolve({
          updatedScanCount: 2,
          updatedPostMediaCount: 1,
        }),
      config: () => config,
    },
  );

  assertEquals(headKeys, [
    `public_uploads/free/${userId}/old.webp`,
    restoredKey,
  ]);
  assertEquals(result, {
    status: "repaired",
    replacementUrl,
    updatedScanCount: 2,
    updatedPostMediaCount: 1,
  });
});

Deno.test("scan image repair rolls back promotion if metadata persistence fails", async () => {
  const deletedKeys: string[] = [];
  await assertRejects(
    () =>
      repairOwnedScanImage(userId, sourceUrl, restoredKey, supabase, {
        referenceExists: () => Promise.resolve(true),
        headObject: (key) =>
          Promise.resolve(
            new Response(null, {
              status: key === restoredKey ? 200 : 404,
            }),
          ),
        tierForUser: () => Promise.resolve("free"),
        promoteMedia: () => Promise.resolve([replacementUrl]),
        persistRepair: () => Promise.reject(new Error("database unavailable")),
        deleteObject: (key) => {
          deletedKeys.push(key);
          return Promise.resolve(new Response(null, { status: 204 }));
        },
        config: () => config,
      }),
    Error,
    "database unavailable",
  );

  assertEquals(deletedKeys, [
    `public_uploads/pro/${userId}/repair_new.webp`,
  ]);
});

Deno.test("scan image repair never deletes a replacement after an ambiguous metadata response", async () => {
  const deletedKeys: string[] = [];
  const error = await assertRejects(() =>
    repairOwnedScanImage(userId, sourceUrl, restoredKey, supabase, {
      referenceExists: () => Promise.resolve(true),
      headObject: (key) =>
        Promise.resolve(
          new Response(null, {
            status: key === restoredKey ? 200 : 404,
          }),
        ),
      tierForUser: () => Promise.resolve("pro"),
      promoteMedia: () => Promise.resolve([replacementUrl]),
      persistRepair: () =>
        Promise.reject(
          new ScanImageRepairPersistenceOutcomeUnknownError(
            "atomic repair response was lost",
          ),
        ),
      deleteObject: (key) => {
        deletedKeys.push(key);
        return Promise.resolve(new Response(null, { status: 204 }));
      },
      config: () => config,
    })
  );

  assertEquals(deletedKeys, []);
  assertEquals(error instanceof PublicHttpError, true);
  assertEquals((error as PublicHttpError).status, 503);
  assertEquals(
    (error as PublicHttpError).code,
    "scan_image_repair_persistence_unknown",
  );
});
