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
      return jsonResponse({
        error: "Invalid payload. Expected an array of 'collections'.",
      }, 400);
    }

    const MAX_COLLECTIONS = 200;
    if (collections.length > MAX_COLLECTIONS) {
      return jsonResponse({
        error: `Too many collections (max ${MAX_COLLECTIONS}).`,
      }, 400);
    }

    const validCollections = collections.filter((c) => !c.is_deleted);
    const deletedCollections = collections.filter((c) => c.is_deleted);
    const activeIds = validCollections.map((c) => c.id);

    // 0. Process explicit deletions first.
    if (deletedCollections.length > 0) {
      const { error: explicitDeleteError } = await supabaseAdmin
        .from("collections")
        .delete()
        .in("id", deletedCollections.map((c) => c.id));
      if (explicitDeleteError) {
        console.error(
          "Explicit collection deletion error:",
          explicitDeleteError,
        );
      }
    }

    // Build the full desired membership set from the client payload.
    const desiredMappings: { collection_id: string; scan_id: string }[] = [];
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

    // 1. Batch upsert active collections + fetch existing memberships concurrently —
    //    these two operations are independent and can be parallelised.
    const [upsertResult, existingMembershipsResult] = await Promise.all([
      validCollections.length > 0
        ? supabaseAdmin.from("collections").upsert(
          validCollections.map((c) => ({
            id: c.id,
            user_id: user.id,
            name: c.name,
            created_at: c.created_at,
          })),
          { onConflict: "id" },
        )
        : Promise.resolve({ error: null }),
      activeIds.length > 0
        ? supabaseAdmin.from("collection_scans").select(
          "collection_id, scan_id",
        ).in("collection_id", activeIds).returns<
          { collection_id: string; scan_id: string }[]
        >()
        : Promise.resolve({ data: [], error: null }),
    ]);

    if (upsertResult.error) {
      console.error("Batch upsert error:", upsertResult.error);
    }

    // 2. Diff-based membership sync — only write the delta, not the entire set.
    if (activeIds.length > 0) {
      type MembershipRow = { collection_id: string; scan_id: string };
      const existingMemberships: MembershipRow[] =
        existingMembershipsResult.data ?? [];

      const membershipKey = (cid: string, sid: string) => `${cid}::${sid}`;
      const existingSet = new Set(
        existingMemberships.map((m) =>
          membershipKey(m.collection_id, m.scan_id)
        ),
      );
      const desiredSet = new Set(
        desiredMappings.map((m) => membershipKey(m.collection_id, m.scan_id)),
      );

      const toAdd = desiredMappings.filter((m) =>
        !existingSet.has(membershipKey(m.collection_id, m.scan_id))
      );
      const toRemove = existingMemberships.filter((m) =>
        !desiredSet.has(membershipKey(m.collection_id, m.scan_id))
      );

      const membershipOps: Promise<unknown>[] = [];

      if (toRemove.length > 0) {
        // Group removals by collection_id so each delete hits one index seek, not a full scan.
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
              supabaseAdmin.from("collection_scans")
                .delete()
                .eq("collection_id", collectionId)
                .in("scan_id", scanIds),
            ),
          );
        }
      }

      if (toAdd.length > 0) {
        // Pre-validate scan IDs to prevent FK violations from aborting the entire batch.
        // Scans that haven't synced yet are safely ignored and will map on the next sync phase.
        const scanIdsToAdd = [
          ...new Set(toAdd.map((m) => m.scan_id)),
        ];
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

    return jsonResponse({
      success: true,
      message: "Collections synchronized successfully.",
    }, 200);
  })
);
