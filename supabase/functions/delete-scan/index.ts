import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { getR2Config, deleteR2Objects } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const requestBody = await req.json();
    const { scanId } = requestBody;

    if (!scanId) {
      return jsonResponse({ error: "Missing 'scanId' parameter in request body." }, 400);
    }

    // 1. Fetch the scan record
    const { data: scan, error: fetchError } = await supabaseAdmin
      .from("scans")
      .select("id, user_id, image_storage_urls")
      .eq("id", scanId)
      .single();

    // If the scan doesn't exist remotely, treat as success — offline sync will drop it cleanly.
    if (fetchError || !scan) {
      console.log(`Scan ${scanId} not found remotely; skipping for offline sync.`);
      return jsonResponse({ success: true, message: "Scan not found remotely." }, 200);
    }

    // 2. Verify ownership before deletion (IDOR protection)
    if (scan.user_id !== user.id) {
      console.error(`IDOR attempt: User ${user.id} tried to delete scan ${scanId} owned by ${scan.user_id}`);
      return jsonResponse({ error: "Forbidden: You do not have permission to delete this record." }, 403);
    }

    // 3. Delete images from R2
    if (scan.image_storage_urls && Array.isArray(scan.image_storage_urls)) {
      const r2Config = getR2Config();
      await deleteR2Objects(scan.image_storage_urls, r2Config);
    }

    // 4. Delete scan from database
    const { error: deleteError } = await supabaseAdmin
      .from("scans")
      .delete()
      .eq("id", scanId);

    if (deleteError) {
      console.error(`Database deletion failed for ${scanId}:`, deleteError);
      return jsonResponse({ error: "Internal Server Error: Failed to delete scan record." }, 500);
    }

    console.log(`Deleted scan ${scanId} for user ${user.id}`);

    return jsonResponse({ success: true, message: "Scan deleted." }, 200);
  })
);
