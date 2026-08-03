import { SupabaseClient } from "@supabase/supabase-js";
import { MembershipRow, SyncCollectionPayload } from "./types.ts";

interface OwnedCollectionResult {
  collection_id: string;
  accepted: boolean;
}

/**
 * Atomically inserts new collections and updates mutable fields only when an
 * existing row belongs to `userId`. The database returns rejected (foreign)
 * IDs so callers can skip them without turning one stale offline UUID into a
 * failed sync.
 */
export async function upsertOwnedCollections(
  userId: string,
  collections: SyncCollectionPayload[],
  supabaseAdmin: SupabaseClient,
): Promise<{ ownedCollections: SyncCollectionPayload[]; ownedIds: string[] }> {
  if (collections.length === 0) {
    return { ownedCollections: [], ownedIds: [] };
  }

  const { data, error } = await supabaseAdmin.rpc(
    "upsert_owned_collections",
    {
      p_user_id: userId,
      p_collections: collections.map((collection) => ({
        id: collection.id,
        name: collection.name,
        created_at: collection.created_at,
      })),
    },
  );

  if (error) {
    throw new Error(`Owned collection upsert failed: ${error.message}`);
  }

  const acceptedIds = new Set(
    ((data ?? []) as OwnedCollectionResult[])
      .filter((row) => row.accepted === true)
      .map((row) => row.collection_id),
  );
  const rejectedIds = new Set(
    collections
      .map((collection) => collection.id)
      .filter((id) => !acceptedIds.has(id)),
  );

  if (rejectedIds.size > 0) {
    console.warn(
      `[sync-collections] Skipping ${rejectedIds.size} rejected collection ID(s) for user ${userId}.`,
    );
  }

  const ownedCollections = collections.filter((collection) =>
    acceptedIds.has(collection.id)
  );
  return { ownedCollections, ownedIds: ownedCollections.map((c) => c.id) };
}

export async function deleteCollections(
  deletedCollections: SyncCollectionPayload[],
  userId: string,
  supabaseAdmin: SupabaseClient,
) {
  if (deletedCollections.length === 0) return;

  // IDOR guard: scope deletion to the requesting user so a crafted payload cannot
  // delete collections owned by another user.
  const { error: explicitDeleteError } = await supabaseAdmin
    .from("collections")
    .delete()
    .in("id", deletedCollections.map((c) => c.id))
    .eq("user_id", userId);

  if (explicitDeleteError) {
    // Throw so the caller gets a 500 rather than a silent success — collections the
    // user intended to delete must not silently remain in the DB.
    throw new Error(
      `Collection deletion failed: ${explicitDeleteError.message}`,
    );
  }
}

export async function fetchCollectionMemberships(
  ownedIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<MembershipRow[]> {
  const existingMemberships: MembershipRow[] = [];
  const pageSize = 1000;

  if (ownedIds.length > 0) {
    let cursor: MembershipRow | undefined;
    while (true) {
      let query = supabaseAdmin
        .from("collection_scans")
        .select("collection_id, scan_id")
        .in("collection_id", ownedIds)
        .order("collection_id", { ascending: true })
        .order("scan_id", { ascending: true })
        .limit(pageSize);

      if (cursor) {
        query = query.or(
          `collection_id.gt.${cursor.collection_id},and(collection_id.eq.${cursor.collection_id},scan_id.gt.${cursor.scan_id})`,
        );
      }

      const { data, error } = await query.returns<MembershipRow[]>();

      if (error) {
        throw new Error(`Membership fetch failed: ${error.message}`);
      }
      if (!data?.length) {
        break;
      }

      existingMemberships.push(...data);
      if (data.length < pageSize) {
        break;
      }
      cursor = data[data.length - 1];
    }
  }

  return existingMemberships;
}

export async function syncMembershipDelta(
  userId: string,
  ownedCollections: SyncCollectionPayload[],
  existingMemberships: MembershipRow[],
  ownedIds: string[],
  supabaseAdmin: SupabaseClient,
) {
  if (ownedIds.length === 0) return;

  const desiredMappings: MembershipRow[] = [];
  for (const collection of ownedCollections) {
    if (collection.scan_ids && collection.scan_ids.length > 0) {
      for (const scanId of collection.scan_ids) {
        desiredMappings.push({
          collection_id: collection.id,
          scan_id: scanId,
        });
      }
    }
  }

  const membershipKey = (cid: string, sid: string) => `${cid}::${sid}`;

  const existingSet = new Set(
    existingMemberships.map((m) => membershipKey(m.collection_id, m.scan_id)),
  );
  const desiredSet = new Set(
    desiredMappings.map((m) => membershipKey(m.collection_id, m.scan_id)),
  );

  const toAdd = desiredMappings.filter(
    (m) => !existingSet.has(membershipKey(m.collection_id, m.scan_id)),
  );
  const toRemove = existingMemberships.filter(
    (m) => !desiredSet.has(membershipKey(m.collection_id, m.scan_id)),
  );

  if (toRemove.length > 0) {
    const removeByCollection = new Map<string, string[]>();
    for (const m of toRemove) {
      if (!removeByCollection.has(m.collection_id)) {
        removeByCollection.set(m.collection_id, []);
      }
      removeByCollection.get(m.collection_id)!.push(m.scan_id);
    }

    for (const [collectionId, scanIds] of removeByCollection) {
      const deleteChunkSize = 200;
      for (let i = 0; i < scanIds.length; i += deleteChunkSize) {
        const chunk = scanIds.slice(i, i + deleteChunkSize);
        const { error } = await supabaseAdmin
          .from("collection_scans")
          .delete()
          .eq("collection_id", collectionId)
          .in("scan_id", chunk);

        if (error) {
          throw new Error(`Membership delete failed: ${error.message}`);
        }
      }
    }
  }

  if (toAdd.length > 0) {
    const insertChunkSize = 1000;
    let insertedCount = 0;
    for (let i = 0; i < toAdd.length; i += insertChunkSize) {
      const chunk = toAdd.slice(i, i + insertChunkSize);
      const { data, error } = await supabaseAdmin.rpc(
        "insert_owned_collection_scans",
        {
          p_user_id: userId,
          p_rows: chunk,
        },
      );

      if (error) {
        throw new Error(`Membership insert failed: ${error.message}`);
      }

      insertedCount += Array.isArray(data) ? data.length : 0;
    }

    if (insertedCount < toAdd.length) {
      console.warn(
        `[sync-collections] Skipped ${
          toAdd.length - insertedCount
        } membership(s) whose collection or scan is unavailable to this owner.`,
      );
    }
  }
}
