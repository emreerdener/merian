import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing or invalid Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    
    // Validate the session natively against GoTrue to handle ES256 tokens securely
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } }
    });

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();

    if (authError || !user) {
      console.error("Auth Rejection:", authError);
      return new Response(JSON.stringify({ error: "Invalid token signature" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

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
      const r2AccountId = Deno.env.get("R2_ACCOUNT_ID") || "";
      const r2Bucket = Deno.env.get("R2_BUCKET_NAME") || "";
      
      const aws = new AwsClient({
        accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID") || "",
        secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY") || "",
        region: "auto",
      });

      await Promise.allSettled(
        scan.image_storage_urls.map(async (url: string) => {
          try {
            console.log(`Deleting from R2: ${url}`);
            
            // Reconstruct internal S3 API bounding since the db now stores the safe public web R2 endpoints
            const s3Url = url.replace(
              "https://pub-fe95d8ff28ea4debbcbdc1f38de77444.r2.dev/",
              `https://${r2AccountId}.r2.cloudflarestorage.com/${r2Bucket}/`
            );
            
            await aws.fetch(s3Url, { method: "DELETE" });
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

  } catch (err) {
    console.error("Internal Error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
