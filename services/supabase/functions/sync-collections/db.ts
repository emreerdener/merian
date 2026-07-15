import { SupabaseClient } from "@supabase/supabase-js";
import { MembershipRow, SyncCollectionPayload } from "./types.ts";

/// Queries the collections table for any incoming IDs that are already owned by a
/// different user. Returns a filtered copy of `collections` that contains only rows
/// safe to upsert/delete — ones that either don't exist yet (new) or are owned by
/// `userId` (legitimate update). Logs a warning when IDOR attempts are detected.
export async function filterOwnedCollections(
  userId: string,
  collections: SyncCollectionPayload[],
  supabaseAdmin: SupabaseClient,
): Promise<{ ownedCollections: SyncCollectionPayload[]; ownedIds: string[] }> {
  if (collections.length === 0) {
    return { ownedCollections: [], ownedIds: [] };
  }

  const { data: existing } = await supabaseAdmin
    .from("collections")
    .select("id, user_id")
    .in("id", collections.map((c) => c.id));

  const foreignIds = new Set(
    (existing ?? [])
      .filter((row: { id: string; user_id: string }) => row.user_id !== userId)
      .map((row: { id: string; user_id: string }) => row.id),
  );

  if (foreignIds.size > 0) {
    console.warn(
      `[sync-collections] IDOR blocked: ${foreignIds.size} collection ID(s) belong to a different user (user: ${userId}). Skipping.`,
    );
  }

  const ownedCollections = collections.filter((c) => !foreignIds.has(c.id));
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

export async function upsertCollectionsAndFetchMemberships(
  userId: string,
  ownedCollections: SyncCollectionPayload[],
  ownedIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<MembershipRow[]> {
  if (ownedCollections.length > 0) {
    const { error: upsertError } = await supabaseAdmin.from("collections")
      .upsert(
        ownedCollections.map((c) => ({
          id: c.id,
          user_id: userId,
          name: c.name,
          created_at: c.created_at,
        })),
        { onConflict: "id" },
      );

    if (upsertError) {
      throw new Error(`Batch collection upsert failed: ${upsertError.message}`);
    }
  }

  const existingMemberships: MembershipRow[] = [];
  const pageSize = 1000;

  if (ownedIds.length > 0) {
    let from = 0;
    while (true) {
      const { data, error } = await supabaseAdmin
        .from("collection_scans")
        .select("collection_id, scan_id")
        .in("collection_id", ownedIds)
        .order("collection_id", { ascending: true })
        .order("scan_id", { ascending: true })
        .range(from, from + pageSize - 1)
        .returns<MembershipRow[]>();

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
      from += pageSize;
    }
  }

  return existingMemberships;
}

export async function syncMembershipDelta(
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
    const scanIdsToAdd = [...new Set(toAdd.map((m) => m.scan_id))];
    const validScanIds = new Set<string>();
    const validateChunkSize = 200;

    for (let i = 0; i < scanIdsToAdd.length; i += validateChunkSize) {
      const chunk = scanIdsToAdd.slice(i, i + validateChunkSize);
      const { data, error: validateError } = await supabaseAdmin
        .from("scans")
        .select("id")
        .in("id", chunk)
        .returns<{ id: string }[]>();

      if (validateError) {
        throw new Error(`Scan validation DB error: ${validateError.message}`);
      }
      for (const row of data ?? []) {
        validScanIds.add(row.id);
      }
    }

    const safeToAdd = toAdd.filter((m) => validScanIds.has(m.scan_id));

    if (safeToAdd.length > 0) {
      const insertChunkSize = 1000;
      for (let i = 0; i < safeToAdd.length; i += insertChunkSize) {
        const chunk = safeToAdd.slice(i, i + insertChunkSize);
        const { error } = await supabaseAdmin.from("collection_scans").upsert(
          chunk,
          {
            onConflict: "collection_id,scan_id",
            ignoreDuplicates: true,
          },
        );

        if (error) {
          throw new Error(`Membership insert failed: ${error.message}`);
        }
      }
    } else {
      console.warn(
        "Skipped adding collection mappings because none of the scan IDs exist in DB yet.",
      );
    }
  }
}
