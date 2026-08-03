import { assertEquals, assertRejects } from "@std/assert";
import {
  fetchCollectionMemberships,
  syncMembershipDelta,
  upsertOwnedCollections,
} from "./db.ts";
import type { MembershipRow, SyncCollectionPayload } from "./types.ts";

function collection(
  id = crypto.randomUUID(),
  scanIds: string[] = [],
): SyncCollectionPayload {
  return {
    id,
    name: `Collection ${id}`,
    created_at: "2026-08-03T12:00:00.000Z",
    is_deleted: false,
    scan_ids: scanIds,
  };
}

Deno.test("upsertOwnedCollections accepts owned/new IDs and skips rejected IDs", async () => {
  const accepted = collection();
  const rejected = collection();
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve({
        data: [
          { collection_id: accepted.id, accepted: true },
          { collection_id: rejected.id, accepted: false },
        ],
        error: null,
      });
    },
  };

  const result = await upsertOwnedCollections(
    "user-1",
    [accepted, rejected],
    // deno-lint-ignore no-explicit-any
    client as any,
  );

  assertEquals(result.ownedIds, [accepted.id]);
  assertEquals(result.ownedCollections, [accepted]);
  assertEquals(calls, [{
    name: "upsert_owned_collections",
    args: {
      p_user_id: "user-1",
      p_collections: [{
        id: accepted.id,
        name: accepted.name,
        created_at: accepted.created_at,
      }, {
        id: rejected.id,
        name: rejected.name,
        created_at: rejected.created_at,
      }],
    },
  }]);
});

Deno.test("upsertOwnedCollections fails closed when the ownership RPC errors", async () => {
  let downstreamCalls = 0;
  const client = {
    rpc: () => {
      downstreamCalls += 1;
      return Promise.resolve({
        data: null,
        error: { message: "database unavailable" },
      });
    },
    from: () => {
      downstreamCalls += 1;
      throw new Error("must not be reached");
    },
  };

  await assertRejects(
    () =>
      upsertOwnedCollections(
        "user-1",
        [collection()],
        // deno-lint-ignore no-explicit-any
        client as any,
      ),
    Error,
    "Owned collection upsert failed",
  );
  assertEquals(downstreamCalls, 1);
});

Deno.test("fetchCollectionMemberships advances with a composite cursor", async () => {
  const collectionIdA = "00000000-0000-0000-0000-00000000000a";
  const collectionIdB = "00000000-0000-0000-0000-00000000000b";
  const limitsRequested: number[] = [];
  const cursorFilters: string[] = [];
  const collectionFilters: string[][] = [];
  const firstPage = [
    ...Array.from({ length: 999 }, (_, index) => ({
      collection_id: collectionIdA,
      scan_id: `scan-${String(index).padStart(4, "0")}`,
    })),
    { collection_id: collectionIdB, scan_id: "scan-0000" },
  ];

  const client = {
    from: (table: string) => {
      if (table !== "collection_scans") {
        throw new Error(`Unexpected table: ${table}`);
      }
      return {
        select: () => ({
          in: (_column: string, values: string[]) => {
            collectionFilters.push(values);
            return {
              order: () => ({
                order: () => ({
                  limit: (limit: number) => {
                    limitsRequested.push(limit);
                    let cursorFilter: string | undefined;
                    const page = {
                      or: (filter: string) => {
                        cursorFilter = filter;
                        cursorFilters.push(filter);
                        return page;
                      },
                      returns: () =>
                        Promise.resolve({
                          data: cursorFilter
                            ? [{
                              collection_id: collectionIdB,
                              scan_id: "scan-0001",
                            }]
                            : firstPage,
                          error: null,
                        }),
                    };
                    return page;
                  },
                }),
              }),
            };
          },
        }),
      };
    },
  };

  const memberships = await fetchCollectionMemberships(
    [collectionIdA, collectionIdB],
    // deno-lint-ignore no-explicit-any
    client as any,
  );

  assertEquals(memberships.length, 1001);
  assertEquals(collectionFilters, [
    [collectionIdA, collectionIdB],
    [collectionIdA, collectionIdB],
  ]);
  assertEquals(limitsRequested, [1000, 1000]);
  assertEquals(cursorFilters, [
    `collection_id.gt.${collectionIdB},and(collection_id.eq.${collectionIdB},scan_id.gt.scan-0000)`,
  ]);
});

Deno.test("syncMembershipDelta inserts through the owner-scoped RPC", async () => {
  const scanId = crypto.randomUUID();
  const payload = collection(crypto.randomUUID(), [scanId]);
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      rpcCalls.push({ name, args });
      return Promise.resolve({
        data: [{ collection_id: payload.id, scan_id: scanId }],
        error: null,
      });
    },
    from: () => {
      throw new Error("No direct membership insert should occur");
    },
  };

  await syncMembershipDelta(
    "user-1",
    [payload],
    [],
    [payload.id],
    // deno-lint-ignore no-explicit-any
    client as any,
  );

  assertEquals(rpcCalls, [{
    name: "insert_owned_collection_scans",
    args: {
      p_user_id: "user-1",
      p_rows: [{ collection_id: payload.id, scan_id: scanId }],
    },
  }]);
});

Deno.test("syncMembershipDelta surfaces owner-scoped membership RPC errors", async () => {
  const payload = collection(crypto.randomUUID(), [crypto.randomUUID()]);
  const client = {
    rpc: () =>
      Promise.resolve({ data: null, error: { message: "RPC unavailable" } }),
    from: () => {
      throw new Error("unexpected direct table call");
    },
  };

  await assertRejects(
    () =>
      syncMembershipDelta(
        "user-1",
        [payload],
        [],
        [payload.id],
        // deno-lint-ignore no-explicit-any
        client as any,
      ),
    Error,
    "Membership insert failed",
  );
});

Deno.test("syncMembershipDelta surfaces membership deletion failures", async () => {
  const payload = collection();
  const membership: MembershipRow = {
    collection_id: payload.id,
    scan_id: crypto.randomUUID(),
  };
  const client = {
    from: (table: string) => {
      if (table !== "collection_scans") throw new Error("unexpected table");
      return {
        delete: () => ({
          eq: () => ({
            in: () =>
              Promise.resolve({
                error: { message: "delete denied" },
              }),
          }),
        }),
      };
    },
  };

  await assertRejects(
    () =>
      syncMembershipDelta(
        "user-1",
        [payload],
        [membership],
        [payload.id],
        // deno-lint-ignore no-explicit-any
        client as any,
      ),
    Error,
    "Membership delete failed",
  );
});

Deno.test("syncMembershipDelta does not touch the database without accepted IDs", async () => {
  const client = {
    from: (): never => {
      throw new Error("from() must not be called");
    },
    rpc: (): never => {
      throw new Error("rpc() must not be called");
    },
  };

  await syncMembershipDelta(
    "user-1",
    [],
    [],
    [],
    // deno-lint-ignore no-explicit-any
    client as any,
  );
});
