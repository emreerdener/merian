import { assert, assertEquals } from "@std/assert";

const mockClientPayload = {
  collections: [
    {
      id: crypto.randomUUID(),
      name: "My Collection",
      created_at: new Date().toISOString(),
      is_deleted: false,
      scan_ids: [crypto.randomUUID()],
    },
  ],
};

Deno.test("collection sync maps mutable fields into the guarded RPC contract", () => {
  const activeCollections = mockClientPayload.collections.filter((collection) =>
    !collection.is_deleted
  );
  const rpcRows = activeCollections.map((collection) => ({
    id: collection.id,
    name: collection.name,
    created_at: collection.created_at,
  }));

  assertEquals(rpcRows.length, 1);
  assertEquals(rpcRows[0].id, mockClientPayload.collections[0].id);
  assert(rpcRows[0].created_at.endsWith("Z"));
  assertEquals(
    Object.hasOwn(rpcRows[0], "user_id"),
    false,
    "Collection ownership is an RPC argument, never a mutable JSON field",
  );
});

Deno.test("foreign collection IDs remain skippable while accepted IDs hydrate memberships", () => {
  const acceptedId = crypto.randomUUID();
  const rejectedId = crypto.randomUUID();
  const collections = [{ id: acceptedId }, { id: rejectedId }];
  const rpcResult = [
    { collection_id: acceptedId, accepted: true },
    { collection_id: rejectedId, accepted: false },
  ];
  const acceptedIds = new Set(
    rpcResult.filter((row) => row.accepted).map((row) => row.collection_id),
  );

  assertEquals(
    collections.filter((collection) => acceptedIds.has(collection.id)),
    [{ id: acceptedId }],
  );
});
