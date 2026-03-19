import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { getR2Config } from "../_shared/aws.ts";
import { withEdgeHandler, jsonResponse } from "../_shared/edgeHandler.ts";

serve((req: Request) => withEdgeHandler(req, async (user, supabaseAdmin) => {
    const requestBody = await req.json();
    const { scanId } = requestBody;

    if (!scanId) {
      return jsonResponse({ error: "Missing scanId in request body" }, 400);
    }

    // Process deletion
    // 1. Fetch the scan
    const { data: scan, error: fetchError } = await supabaseAdmin
      .from("scans")
      .select("id, user_id, image_storage_urls")
      .eq("id", scanId)
      .single();

    if (fetchError || !scan) {
      console.log(`Scan ${scanId} not found, likely an offline scan that never synced.`);
      return jsonResponse({ success: true, message: "Scan not found remotely." }, 200);
    }

    // 2. Authorization check
    if (scan.user_id !== user.id) {
      console.error(`IDOR attempt: User ${user.id} tried to delete scan ${scanId} owned by ${scan.user_id}`);
      return jsonResponse({ error: "Forbidden: You do not own this scan" }, 403);
    }

    // 3. R2 Image Erasure
    if (scan.image_storage_urls && Array.isArray(scan.image_storage_urls)) {
      const { s3Client, bucketName, endpoint } = getR2Config();

      await Promise.allSettled(
        scan.image_storage_urls.map(async (url: string) => {
          try {
            console.log(`Deleting from R2: ${url}`);
            
            // Reconstruct internal S3 API bounding since the db now stores the safe public web R2 endpoints
            const s3Url = url.replace(
              "https://media.merian.app/",
              `${endpoint}/${bucketName}/`
            );
            
            await s3Client.fetch(s3Url, { method: "DELETE" });
          } catch (e) {
            console.error(`Failed to delete image at ${url} from R2:`, e);
          }
        })
      );
    }

    // 4. Database Erasure
    const { error: deleteError } = await supabaseAdmin
      .from("scans")
      .delete()
      .eq("id", scanId);

    if (deleteError) {
      console.error("Database deletion error:", deleteError);
      return jsonResponse({ error: "Failed to delete scan from database" }, 500);
    }
    console.log(`Successfully deleted scan ${scanId} for user ${user.id}`);

    return jsonResponse({ success: true }, 200);
}));
