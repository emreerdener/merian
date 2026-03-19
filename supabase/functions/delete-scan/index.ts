import { serve } from "@std/http/server.ts";
import { getR2Config } from "../_shared/aws.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) => withEdgeHandler(req, async (user, supabaseAdmin) => {
    const requestBody = await req.json();
    const { scanId } = requestBody;

    if (!scanId) {
      return new Response(JSON.stringify({ error: "Missing scanId in request body" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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
      return new Response(JSON.stringify({ success: true, message: "Scan not found remotely." }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Authorization check
    if (scan.user_id !== user.id) {
      console.error(`IDOR attempt: User ${user.id} tried to delete scan ${scanId} owned by ${scan.user_id}`);
      return new Response(JSON.stringify({ error: "Forbidden: You do not own this scan" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
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
      return new Response(JSON.stringify({ error: "Failed to delete scan from database" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    console.log(`Successfully deleted scan ${scanId} for user ${user.id}`);

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}));
