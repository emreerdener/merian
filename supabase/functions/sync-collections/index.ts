import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

interface SyncCollectionPayload {
  id: string;
  name: string;
  created_at: string;
  scan_ids: string[];
  is_deleted?: boolean;
}

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const requestBody = await req.json();
    const collections: SyncCollectionPayload[] = requestBody.collections;

    if (!collections || !Array.isArray(collections)) {
      return jsonResponse({ error: "Invalid payload. Expected an array of 'collections'." }, 400);
    }

    const MAX_COLLECTIONS = 200;
    if (collections.length > MAX_COLLECTIONS) {
      return jsonResponse({ error: `Too many collections (max ${MAX_COLLECTIONS}).` }, 400);
    }

    const validCollections = collections.filter(c => !c.is_deleted);
    const activeIds = validCollections.map(c => c.id);

    // Build the full desired membership set from the client payload.
    const desiredMappings: { collection_id: string; scan_id: string }[] = [];
    for (const collection of validCollections) {
      if (collection.scan_ids && collection.scan_ids.length > 0) {
        for (const scanId of collection.scan_ids) {
          desiredMappings.push({ collection_id: collection.id, scan_id: scanId });
        }
      }
    }

    // 1. Batch upsert active collections + fetch existing memberships concurrently —
    //    these two operations are independent and can be parallelised.
    const [upsertResult, existingMembershipsResult, existingCollectionsResult] = await Promise.all([
      validCollections.length > 0
        ? supabaseAdmin.from("collections").upsert(
            validCollections.map(c => ({ id: c.id, user_id: user.id, name: c.name, created_at: c.created_at })),
            { onConflict: "id" }
          )
        : Promise.resolve({ error: null }),
      activeIds.length > 0
        ? supabaseAdmin.from("collection_scans").select("collection_id, scan_id").in("collection_id", activeIds)
        : Promise.resolve({ data: [], error: null }),
      supabaseAdmin.from("collections").select("id").eq("user_id", user.id),
    ]);

    if (upsertResult.error) console.error("Batch upsert error:", upsertResult.error);

    // 2. Diff-based membership sync — only write the delta, not the entire set.
    if (activeIds.length > 0) {
      type MembershipRow = { collection_id: string; scan_id: string };
      const existingMemberships: MembershipRow[] = (existingMembershipsResult.data as MembershipRow[]) ?? [];

      const membershipKey = (cid: string, sid: string) => `${cid}::${sid}`;
      const existingSet = new Set(existingMemberships.map(m => membershipKey(m.collection_id, m.scan_id)));
      const desiredSet  = new Set(desiredMappings.map(m => membershipKey(m.collection_id, m.scan_id)));

      const toAdd    = desiredMappings.filter(m => !existingSet.has(membershipKey(m.collection_id, m.scan_id)));
      const toRemove = existingMemberships.filter(m => !desiredSet.has(membershipKey(m.collection_id, m.scan_id)));

      const membershipOps: Promise<unknown>[] = [];

      if (toRemove.length > 0) {
        // Group removals by collection_id so each delete hits one index seek, not a full scan.
        const removeByCollection = new Map<string, string[]>();
        for (const m of toRemove) {
          if (!removeByCollection.has(m.collection_id)) removeByCollection.set(m.collection_id, []);
          removeByCollection.get(m.collection_id)!.push(m.scan_id);
        }
        for (const [collectionId, scanIds] of removeByCollection) {
          membershipOps.push(
            supabaseAdmin.from("collection_scans")
              .delete()
              .eq("collection_id", collectionId)
              .in("scan_id", scanIds)
          );
        }
      }

      if (toAdd.length > 0) {
        // FK violations are expected for scans not yet synced; insert with ignore.
        membershipOps.push(
          supabaseAdmin.from("collection_scans").upsert(toAdd, { onConflict: "collection_id,scan_id", ignoreDuplicates: true })
        );
      }

      if (membershipOps.length > 0) {
        const membershipResults = await Promise.allSettled(membershipOps);
        for (const r of membershipResults) {
          if (r.status === "rejected") console.error("Membership delta op failed:", r.reason);
        }
      }
    }

    // 3. Diff-delete collections no longer in the active set.
    if (existingCollectionsResult.data) {
      const existingIds = (existingCollectionsResult.data as { id: string }[]).map(e => e.id);
      const toDelete = existingIds.filter(id => !activeIds.includes(id));

      if (toDelete.length > 0) {
        const { error: deleteError } = await supabaseAdmin
          .from("collections")
          .delete()
          .in("id", toDelete);

        if (deleteError) console.error("Diff collection deletion error:", deleteError);
      }
    }

    return jsonResponse({ success: true, message: "Collections synchronized successfully." }, 200);
  })
);
