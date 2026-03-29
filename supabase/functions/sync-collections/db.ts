import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { SyncCollectionPayload, MembershipRow } from "./types.ts";

export async function deleteCollections(
  deletedCollections: SyncCollectionPayload[],
  supabaseAdmin: SupabaseClient,
) {
  if (deletedCollections.length === 0) return;

  const { error: explicitDeleteError } = await supabaseAdmin
    .from("collections")
    .delete()
    .in(
      "id",
      deletedCollections.map((c) => c.id),
    );

  if (explicitDeleteError) {
    console.error("Explicit collection deletion error:", explicitDeleteError);
  }
}

export async function upsertCollectionsAndFetchMemberships(
  userId: string,
  validCollections: SyncCollectionPayload[],
  activeIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<MembershipRow[]> {
  const [upsertResult, existingMembershipsResult] = await Promise.all([
    validCollections.length > 0
      ? supabaseAdmin.from("collections").upsert(
          validCollections.map((c) => ({
            id: c.id,
            user_id: userId,
            name: c.name,
            created_at: c.created_at,
          })),
          { onConflict: "id" },
        )
      : Promise.resolve({ error: null }),
    activeIds.length > 0
      ? supabaseAdmin
          .from("collection_scans")
          .select("collection_id, scan_id")
          .in("collection_id", activeIds)
          .returns<MembershipRow[]>()
      : Promise.resolve({ data: [], error: null }),
  ]);

  if (upsertResult.error) {
    console.error("Batch upsert error:", upsertResult.error);
  }

  return existingMembershipsResult.data ?? [];
}

export async function syncMembershipDelta(
  validCollections: SyncCollectionPayload[],
  existingMemberships: MembershipRow[],
  activeIds: string[],
  supabaseAdmin: SupabaseClient,
) {
  if (activeIds.length === 0) return;

  const desiredMappings: MembershipRow[] = [];
  for (const collection of validCollections) {
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

  const membershipOps: Promise<unknown>[] = [];

  if (toRemove.length > 0) {
    const removeByCollection = new Map<string, string[]>();
    for (const m of toRemove) {
      if (!removeByCollection.has(m.collection_id)) {
        removeByCollection.set(m.collection_id, []);
      }
      removeByCollection.get(m.collection_id)!.push(m.scan_id);
    }

    for (const [collectionId, scanIds] of removeByCollection) {
      membershipOps.push(
        Promise.resolve(
          supabaseAdmin
            .from("collection_scans")
            .delete()
            .eq("collection_id", collectionId)
            .in("scan_id", scanIds),
        ),
      );
    }
  }

  if (toAdd.length > 0) {
    const scanIdsToAdd = [...new Set(toAdd.map((m) => m.scan_id))];

    const { data: validScans, error: validateError } = await supabaseAdmin
      .from("scans")
      .select("id")
      .in("id", scanIdsToAdd)
      .returns<{ id: string }[]>();

    if (validateError) {
      console.error("Scan validation DB error:", validateError);
    }

    const validScanIds = new Set(validScans?.map((s) => s.id) || []);
    const safeToAdd = toAdd.filter((m) => validScanIds.has(m.scan_id));

    if (safeToAdd.length > 0) {
      membershipOps.push(
        Promise.resolve(
          supabaseAdmin.from("collection_scans").upsert(safeToAdd, {
            onConflict: "collection_id,scan_id",
            ignoreDuplicates: true,
          }),
        ),
      );
    } else {
      console.warn(
        "Skipped adding collection mappings because none of the scan IDs exist in DB yet.",
      );
    }
  }

  if (membershipOps.length > 0) {
    const membershipResults = await Promise.allSettled(membershipOps);
    for (const r of membershipResults) {
      if (r.status === "rejected") {
        console.error("Membership delta promise rejected:", r.reason);
      } else if (r.value && (r.value as { error: unknown }).error) {
        console.error(
          "Membership delta DB error:",
          (r.value as { error: unknown }).error,
        );
      }
    }
  }
}
