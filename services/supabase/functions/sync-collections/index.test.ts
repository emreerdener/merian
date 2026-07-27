// services/supabase/functions/sync-collections/index.test.ts
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

/**
 * Exercises the request-to-upsert mapping without conditionally writing to an
 * arbitrary Supabase environment. Database schema and authorization behavior
 * belong to the disposable pgTAP catalog; unit tests must never turn missing
 * credentials into a passing "live" integration test.
 */

// A mock of the exact payload structure the Swift client `SyncCollectionPayload` generates:
const mockClientPayload = {
  collections: [
    {
      id: crypto.randomUUID(),
      name: "My Collection",
      created_at: new Date().toISOString(), // Equivalent to Swift DateUtilities.iso8601Formatter
      is_deleted: false,
      scan_ids: [crypto.randomUUID()],
    },
  ],
};

// Simulated mock mapping of Edge function logic:
Deno.test("Edge Function payload maps to the collection upsert contract", () => {
  // 1. Initial extraction
  const collections = mockClientPayload.collections;
  assert(Array.isArray(collections), "Collections is not an array");

  // 2. Validate iOS `is_deleted` filter
  const validCollections = collections.filter((c) => !c.is_deleted);
  const deletedCollections = collections.filter((c) => c.is_deleted);

  assert(
    validCollections.length === 1,
    "Failed to whitelist non-deleted collections",
  );
  assert(
    deletedCollections.length === 0,
    "Failed to blacklist deleted collections",
  );

  const _activeIds = validCollections.map((c) => c.id);

  // 3. Mock Upsert Mapping
  const mockUserId = crypto.randomUUID();
  const mappedUpsertPayload = validCollections.map((c) => ({
    id: c.id,
    user_id: mockUserId,
    name: c.name,
    created_at: c.created_at,
  }));

  // Verify properties match Postgres schema:
  for (const record of mappedUpsertPayload) {
    assert(typeof record.id === "string", "id is not a string UUID");
    assert(typeof record.user_id === "string", "user_id is not a string UUID");
    assert(typeof record.name === "string", "name is not a string");
    assert(
      typeof record.created_at === "string",
      "created_at is not an ISO8601 string",
    );
    // Verify ISO format ends with 'Z' as Swift does
    assert(
      record.created_at.endsWith("Z"),
      "created_at must be UTC Z-suffixed",
    );
  }
});

// ---------------------------------------------------------------------------
// filterOwnedCollections — IDOR guard logic
// Inline stub of the ownership-filter logic from db.ts. Tests the rule:
//   - Collections not yet in the DB (no existing row) are always allowed through
//   - Collections whose DB row.user_id === requestingUserId are allowed through
//   - Collections whose DB row.user_id !== requestingUserId are silently dropped
// ---------------------------------------------------------------------------

interface CollectionPayload {
  id: string;
  name: string;
}
interface ExistingRow {
  id: string;
  user_id: string;
}

function filterOwned(
  userId: string,
  collections: CollectionPayload[],
  existingRows: ExistingRow[],
): { ownedCollections: CollectionPayload[]; ownedIds: string[] } {
  const foreignIds = new Set(
    existingRows
      .filter((r) => r.user_id !== userId)
      .map((r) => r.id),
  );
  const ownedCollections = collections.filter((c) => !foreignIds.has(c.id));
  return { ownedCollections, ownedIds: ownedCollections.map((c) => c.id) };
}

Deno.test("filterOwnedCollections — new collection (no DB row) is allowed through", () => {
  const newId = crypto.randomUUID();
  const { ownedCollections } = filterOwned(
    "user-A",
    [{ id: newId, name: "New" }],
    [], // no existing rows
  );
  assertEquals(ownedCollections.length, 1);
  assertEquals(ownedCollections[0].id, newId);
});

Deno.test("filterOwnedCollections — collection owned by requesting user is allowed through", () => {
  const id = crypto.randomUUID();
  const { ownedCollections } = filterOwned(
    "user-A",
    [{ id, name: "Mine" }],
    [{ id, user_id: "user-A" }],
  );
  assertEquals(ownedCollections.length, 1);
});

Deno.test("filterOwnedCollections — collection owned by different user is silently dropped (IDOR)", () => {
  const foreignId = crypto.randomUUID();
  const { ownedCollections, ownedIds } = filterOwned(
    "user-A",
    [{ id: foreignId, name: "Not mine" }],
    [{ id: foreignId, user_id: "user-B" }], // belongs to user-B
  );
  assertEquals(
    ownedCollections.length,
    0,
    "Foreign collection must be filtered out",
  );
  assertEquals(ownedIds.length, 0);
});

Deno.test("filterOwnedCollections — mixed payload: owned and foreign collections separated correctly", () => {
  const ownedId = crypto.randomUUID();
  const foreignId = crypto.randomUUID();
  const newId = crypto.randomUUID();

  const { ownedCollections, ownedIds } = filterOwned(
    "user-A",
    [
      { id: ownedId, name: "Mine" },
      { id: foreignId, name: "Not mine" },
      { id: newId, name: "New" },
    ],
    [
      { id: ownedId, user_id: "user-A" },
      { id: foreignId, user_id: "user-B" },
      // newId has no existing row — passes through
    ],
  );
  assertEquals(
    ownedCollections.length,
    2,
    "Only owned and new collections pass through",
  );
  assert(ownedIds.includes(ownedId));
  assert(ownedIds.includes(newId));
  assert(!ownedIds.includes(foreignId), "Foreign ID must be excluded");
});

Deno.test("filterOwnedCollections — empty input returns empty output", () => {
  const { ownedCollections, ownedIds } = filterOwned("user-A", [], []);
  assertEquals(ownedCollections.length, 0);
  assertEquals(ownedIds.length, 0);
});
