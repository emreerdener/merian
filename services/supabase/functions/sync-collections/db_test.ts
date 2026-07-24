// services/supabase/functions/sync-collections/db_test.ts
//
// Unit tests for syncMembershipDelta error-propagation contract.
// The function now throws instead of swallowing errors via console.error,
// so the controller propagates a 500 and the iOS client retries rather
// than treating a partial failure as confirmed.
//
// These tests mock the SupabaseClient interface to avoid live DB access.

import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  syncMembershipDelta,
  upsertCollectionsAndFetchMemberships,
} from "./db.ts";
import type { MembershipRow, SyncCollectionPayload } from "./types.ts";

// ---------------------------------------------------------------------------
// Minimal SupabaseClient mock helpers
// ---------------------------------------------------------------------------

/** Creates a PostgREST chain mock that resolves to the given result. */
function makeChain(
  result: { data?: unknown; error?: { message: string } | null },
) {
  const chain = {
    from: (_table: string) => chain,
    select: (..._args: unknown[]) => chain,
    eq: (..._args: unknown[]) => chain,
    in: (..._args: unknown[]) => chain,
    delete: () => chain,
    upsert: (..._args: unknown[]) => chain,
    returns: (..._args: unknown[]) => Promise.resolve(result),
    then: (resolve: (v: typeof result) => unknown) =>
      Promise.resolve(result).then(resolve),
  };
  // Make the chain itself awaitable by adding a then method at the top level
  return {
    ...chain,
    [Symbol.for("nodejs.util.inspect.custom")]: () => "[MockChain]",
  };
}

type MockChain = ReturnType<typeof makeChain>;

/** Builds a minimal SupabaseClient mock. All query chains resolve using `defaultResult`. */
function makeMockClient(
  defaultResult: { data?: unknown; error?: { message: string } | null },
): {
  from: (table: string) => MockChain;
} {
  return {
    from: (_table: string) => makeChain(defaultResult),
  };
}

// ---------------------------------------------------------------------------
// syncMembershipDelta — scan validation error
// ---------------------------------------------------------------------------

Deno.test("syncMembershipDelta throws when scan validation DB query fails", async () => {
  const collection: SyncCollectionPayload = {
    id: crypto.randomUUID(),
    name: "Test Collection",
    created_at: new Date().toISOString(),
    is_deleted: false,
    scan_ids: [crypto.randomUUID()],
  };

  // Mock a client where the scan-validation SELECT returns an error.
  // This exercises the `if (validateError) { throw ... }` path added
  // to replace the old `console.error` swallow.
  // The chain must mirror db.ts: .select().in().returns() → Promise
  const errorClient = {
    from: (_table: string) => ({
      select: (..._args: unknown[]) => ({
        in: (..._args: unknown[]) => ({
          returns: (..._args: unknown[]) =>
            Promise.resolve({
              data: null,
              error: { message: "relation 'scans' does not exist" },
            }),
        }),
      }),
      delete: () => ({
        eq: () => ({ in: () => Promise.resolve({ error: null }) }),
      }),
      upsert: (..._args: unknown[]) => Promise.resolve({ error: null }),
    }),
  };

  const existingMemberships: MembershipRow[] = [];

  await assertRejects(
    () =>
      syncMembershipDelta(
        [collection],
        existingMemberships,
        [collection.id],
        // deno-lint-ignore no-explicit-any
        errorClient as any,
      ),
    Error,
    "Scan validation DB error",
    "syncMembershipDelta must throw — not swallow — scan validation failures",
  );
});

// ---------------------------------------------------------------------------
// syncMembershipDelta — membership operation rejection
// ---------------------------------------------------------------------------

Deno.test("syncMembershipDelta throws when a membership delete operation is rejected", async () => {
  const collectionId = crypto.randomUUID();
  const scanId = crypto.randomUUID();

  const collection: SyncCollectionPayload = {
    id: collectionId,
    name: "Collection to remove from",
    created_at: new Date().toISOString(),
    is_deleted: false,
    scan_ids: [], // desired: no scans
  };

  // Existing memberships has one entry that needs to be removed
  const existingMemberships: MembershipRow[] = [
    { collection_id: collectionId, scan_id: scanId },
  ];

  // Mock: scan validation succeeds (no scans to add), but the delete fails
  const rejectClient = {
    from: (_table: string) => ({
      select: (..._args: unknown[]) => ({
        in: (..._args: unknown[]) => Promise.resolve({ data: [], error: null }),
      }),
      delete: () => ({
        eq: (_col: string, _val: string) => ({
          in: (_col: string, _vals: string[]) =>
            Promise.resolve({
              error: { message: "RLS policy denied delete" },
            }),
        }),
      }),
      upsert: (..._args: unknown[]) => Promise.resolve({ error: null }),
    }),
  };

  await assertRejects(
    () =>
      syncMembershipDelta(
        [collection],
        existingMemberships,
        [collectionId],
        // deno-lint-ignore no-explicit-any
        rejectClient as any,
      ),
    Error,
    "Membership delete failed",
    "syncMembershipDelta must surface membership operation DB errors to the caller",
  );
});

// ---------------------------------------------------------------------------
// syncMembershipDelta — happy path: no error thrown on success
// ---------------------------------------------------------------------------

Deno.test("syncMembershipDelta resolves without throwing on success", async () => {
  const collection: SyncCollectionPayload = {
    id: crypto.randomUUID(),
    name: "Happy Collection",
    created_at: new Date().toISOString(),
    is_deleted: false,
    scan_ids: [],
  };

  // All operations succeed
  // deno-lint-ignore no-explicit-any
  const successClient = makeMockClient({ data: [], error: null }) as any;

  // Should not throw
  await syncMembershipDelta([collection], [], [collection.id], successClient);
  assertEquals(
    true,
    true,
    "syncMembershipDelta must resolve cleanly when all operations succeed",
  );
});

// ---------------------------------------------------------------------------
// syncMembershipDelta — short-circuit: empty ownedIds returns immediately
// ---------------------------------------------------------------------------

Deno.test("syncMembershipDelta returns early when ownedIds is empty", async () => {
  // No DB calls should be made; pass a client that throws if called
  const neverCalledClient = {
    from: (_table: string): never => {
      throw new Error("from() must not be called when ownedIds is empty");
    },
  };

  // deno-lint-ignore no-explicit-any
  await syncMembershipDelta([], [], [], neverCalledClient as any);
  assertEquals(
    true,
    true,
    "syncMembershipDelta must return early for empty ownedIds without any DB access",
  );
});

// ---------------------------------------------------------------------------
// upsertCollectionsAndFetchMemberships — keyset-paginated membership fetch
// ---------------------------------------------------------------------------

Deno.test("upsertCollectionsAndFetchMemberships advances memberships with a composite cursor", async () => {
  const collectionIdA = "00000000-0000-0000-0000-00000000000a";
  const collectionIdB = "00000000-0000-0000-0000-00000000000b";
  const limitsRequested: number[] = [];
  const cursorFilters: string[] = [];
  const collectionFilters: string[][] = [];
  let upsertCallCount = 0;
  const firstPage = [
    ...Array.from({ length: 999 }, (_, index) => ({
      collection_id: collectionIdA,
      scan_id: `scan-${String(index).padStart(4, "0")}`,
    })),
    {
      collection_id: collectionIdB,
      scan_id: "scan-0000",
    },
  ];

  const client = {
    from: (table: string) => {
      if (table === "collections") {
        return {
          upsert: (..._args: unknown[]) => {
            upsertCallCount += 1;
            return Promise.resolve({ error: null });
          },
        };
      }

      if (table === "collection_scans") {
        return {
          select: (..._args: unknown[]) => ({
            in: (_column: string, values: string[]) => {
              collectionFilters.push(values);
              return {
                order: (..._orderArgs: unknown[]) => ({
                  order: (..._secondOrderArgs: unknown[]) => ({
                    limit: (limit: number) => {
                      limitsRequested.push(limit);
                      let cursorFilter: string | undefined;
                      const page = {
                        or: (filter: string) => {
                          cursorFilter = filter;
                          cursorFilters.push(filter);
                          return page;
                        },
                        returns: (..._rangeArgs: unknown[]) => {
                          if (!cursorFilter) {
                            return Promise.resolve({
                              data: firstPage,
                              error: null,
                            });
                          }
                          return Promise.resolve({
                            data: [{
                              collection_id: collectionIdB,
                              scan_id: "scan-0001",
                            }],
                            error: null,
                          });
                        },
                      };
                      return page;
                    },
                  }),
                }),
              };
            },
          }),
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  const memberships = await upsertCollectionsAndFetchMemberships(
    "user-1",
    [{
      id: collectionIdA,
      name: "Paged Collection",
      created_at: new Date().toISOString(),
      is_deleted: false,
      scan_ids: [],
    }, {
      id: collectionIdB,
      name: "Second Paged Collection",
      created_at: new Date().toISOString(),
      is_deleted: false,
      scan_ids: [],
    }],
    [collectionIdA, collectionIdB],
    // deno-lint-ignore no-explicit-any
    client as any,
  );

  assertEquals(upsertCallCount, 1);
  assertEquals(memberships.length, 1001);
  assertEquals(collectionFilters, [[collectionIdA, collectionIdB], [
    collectionIdA,
    collectionIdB,
  ]]);
  assertEquals(limitsRequested, [1000, 1000]);
  assertEquals(cursorFilters, [
    `collection_id.gt.${collectionIdB},and(collection_id.eq.${collectionIdB},scan_id.gt.scan-0000)`,
  ]);
});
