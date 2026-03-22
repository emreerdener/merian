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

    const activeIds: string[] = [];

    for (const collection of collections) {
      if (collection.is_deleted) continue; // Skip explicit deletes as we diff anyway
      activeIds.push(collection.id);

      const { error: upsertError } = await supabaseAdmin
        .from("collections")
        .upsert({
          id: collection.id,
          user_id: user.id,
          name: collection.name,
          created_at: collection.created_at
        }, { onConflict: "id" });

      if (upsertError) {
        console.error(`Error upserting collection ${collection.id}:`, upsertError);
        continue;
      }

      await supabaseAdmin
        .from("collection_scans")
        .delete()
        .eq("collection_id", collection.id);

      if (collection.scan_ids && collection.scan_ids.length > 0) {
        const mappings = collection.scan_ids.map(scanId => ({
          collection_id: collection.id,
          scan_id: scanId
        }));
        
        await supabaseAdmin
          .from("collection_scans")
          .insert(mappings);
      }
    }

    // Delete collections not present in the payload (Full Sync)
    if (activeIds.length > 0) {
      const { error: deleteError } = await supabaseAdmin
        .from("collections")
        .delete()
        .eq("user_id", user.id)
        .not("id", "in", `(${activeIds.join(",")})`);
      
      if (deleteError) {
         console.error("Diff deletion error: ", deleteError);
      }
    } else {
      // If payload is empty, they deleted all collections
      await supabaseAdmin.from("collections").delete().eq("user_id", user.id);
    }

    return jsonResponse({ success: true, message: "Collections synchronized successfully." }, 200);
  })
);
