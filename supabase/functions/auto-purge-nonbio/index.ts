import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { getR2Config } from "../_shared/aws.ts";

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method Not Allowed" }), { 
      status: 405, headers: { "Content-Type": "application/json" } 
    });
  }

  // Enforce Service Role Auth
  const expectedAuth = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  const providedAuth = req.headers.get("Authorization");

  if (providedAuth !== expectedAuth) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { 
      status: 401, headers: { "Content-Type": "application/json" } 
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

    // 1. Query non-biological scans older than 30 days
    // Limit to 500 rows to prevent V8 memory starvation
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    const { data: scans, error: fetchError } = await supabaseAdmin
      .from("scans")
      .select("id, image_storage_urls")
      .eq("is_biological_subject", false)
      .lt("timestamp", thirtyDaysAgo.toISOString())
      .limit(500);

    if (fetchError) {
      throw fetchError;
    }

    if (!scans || scans.length === 0) {
      return new Response(JSON.stringify({ message: "No non-biological scans to purge." }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }

    const { s3Client, bucketName, endpoint } = getR2Config();
    const idsToDelete: string[] = [];

    // 2. Iterate and issue DELETE to R2 natively
    for (const scan of scans) {
      idsToDelete.push(scan.id);
      
      const urls: string[] = scan.image_storage_urls || [];
      await Promise.allSettled(
        urls.map(async (url: string) => {
          try {
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
    
    // 3. Execute `.delete().in("id", ...)` on the scans table
    if (idsToDelete.length > 0) {
      const { error: deleteError } = await supabaseAdmin
        .from("scans")
        .delete()
        .in("id", idsToDelete);
        
      if (deleteError) {
        throw deleteError;
      }
    }

    return new Response(JSON.stringify({ success: true, count: idsToDelete.length }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });
    
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return new Response(JSON.stringify({ error: message }), { 
      status: 500, 
      headers: { "Content-Type": "application/json" } 
    });
  }
});
