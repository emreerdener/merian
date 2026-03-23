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

    const validCollections = collections.filter(c => !c.is_deleted);
    const activeIds = validCollections.map(c => c.id);

    // 1. Batch Upsert Collections
    if (validCollections.length > 0) {
      const collectionPayloads = validCollections.map(c => ({
        id: c.id,
        user_id: user.id,
        name: c.name,
        created_at: c.created_at
      }));

      const { error: upsertError } = await supabaseAdmin
        .from("collections")
        .upsert(collectionPayloads, { onConflict: "id" });

      if (upsertError) {
        console.error("Batch upsert error: ", upsertError);
      }
    }

    // 2. Wipe existing collection_scans for active groups to refresh mappings natively
    if (activeIds.length > 0) {
      await supabaseAdmin
        .from("collection_scans")
        .delete()
        .in("collection_id", activeIds);
        
      // 3. Insert mappings, swallowing missing FK scan failures if pending offline queue inserts lag natively
      const allMappings: { collection_id: string; scan_id: string }[] = [];
      for (const collection of validCollections) {
        if (collection.scan_ids && collection.scan_ids.length > 0) {
          const mappings = collection.scan_ids.map(scanId => ({
            collection_id: collection.id,
            scan_id: scanId
          }));
          allMappings.push(...mappings);
        }
      }

      if (allMappings.length > 0) {
        // Execute a native Postgres bulk-insertion to definitively prevent N+1 query meltdowns!
        const { error: insertError } = await supabaseAdmin.from("collection_scans").insert(allMappings);
        if (insertError) {
          console.error("Bulk mapping insert error: ", insertError);
        }
      }
    }

    // 4. Safely diff-delete obsolete collections (Full Sync)
    const { data: existingIdsData } = await supabaseAdmin
      .from("collections")
      .select("id")
      .eq("user_id", user.id);

    if (existingIdsData) {
      const existingIds = existingIdsData.map(e => e.id as string);
      const toDelete = existingIds.filter(id => !activeIds.includes(id));

      if (toDelete.length > 0) {
        const { error: deleteError } = await supabaseAdmin
          .from("collections")
          .delete()
          .in("id", toDelete);
        
        if (deleteError) {
          console.error("Diff deletion error: ", deleteError);
        }
      }
    }

    return jsonResponse({ success: true, message: "Collections synchronized successfully." }, 200);
  })
);
