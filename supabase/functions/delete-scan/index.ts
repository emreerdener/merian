import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { getR2Config } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const requestBody = await req.json();
    const { scanId } = requestBody;

    if (!scanId) {
      return jsonResponse({ error: "Missing 'scanId' parameter in request body." }, 400);
    }

    // 1. Fetch the remote scan payload securely
    const { data: scan, error: fetchError } = await supabaseAdmin
      .from("scans")
      .select("id, user_id, image_storage_urls")
      .eq("id", scanId)
      .single();

    // Soft bypass: If the user deletes a local offline scan before it syncs to the DB,
    // the Cloud Sync queue will harmlessly drop it.
    if (fetchError || !scan) {
      console.log(`Scan ${scanId} not found remotely, explicitly ignoring for Offline Sync queues.`);
      return jsonResponse({ success: true, message: "Scan not found remotely." }, 200);
    }

    // 2. Authorization constraints (IDOR Protection)
    if (scan.user_id !== user.id) {
      console.error(`IDOR attempt: User ${user.id} accessed scan ${scanId} owned by ${scan.user_id}`);
      return jsonResponse({ error: "Forbidden: You do not have permission to delete this record." }, 403);
    }

    // 3. R2 Image Erasure (Cloudflare)
    if (scan.image_storage_urls && Array.isArray(scan.image_storage_urls)) {
      const { s3Client, bucketName, endpoint } = getR2Config();

      await Promise.allSettled(
        scan.image_storage_urls.map(async (url: string) => {
          try {
            console.log(`Obliterating R2 payload: ${url}`);
            
            // Rewrite the internal S3 API binding natively since Postgres stores public Media URLs
            const s3Url = url.replace(
              "https://media.merian.app/",
              `${endpoint}/${bucketName}/`
            );
            
            await s3Client.fetch(s3Url, { method: "DELETE" });
          } catch (e) {
            console.error(`Failed to wipe media at ${url} from Cloudflare R2:`, e);
          }
        })
      );
    }

    // 4. Postgres Database Erasure
    const { error: deleteError } = await supabaseAdmin
      .from("scans")
      .delete()
      .eq("id", scanId);

    if (deleteError) {
      console.error(`Database deletion failed for ${scanId}:`, deleteError);
      return jsonResponse({ error: "Internal Server Error: Failed to drop database row." }, 500);
    }

    console.log(`Successfully annihilated scan ${scanId} for user ${user.id}`);
    
    return jsonResponse({ 
      success: true, 
      message: "Scan securely deleted." 
    }, 200);
  })
);
