// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { deleteR2Objects, getR2Config } from "../_shared/aws.ts";
import { corsHeaders } from "../_shared/http.ts";
import { timingSafeCompare } from "../_shared/http.ts";

import { fetchStaleDomesticatedScans, zeroOutDomesticatedUrls } from "./db.ts";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  // 1. Authenticate the Webhook via Service Role Key natively
  const expectedAuth = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  const providedAuth = req.headers.get("Authorization") ?? "";

  if (!timingSafeCompare(providedAuth, expectedAuth)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

    // 2. Query free tier domesticated scans older than 90 days
    const ninetyDaysAgo = new Date();
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);
    const boundaryIso = ninetyDaysAgo.toISOString();

    const scans = await fetchStaleDomesticatedScans(boundaryIso, supabaseAdmin);

    if (scans.length === 0) {
      return jsonResponse(
        { message: "No expired domesticated scans to purge." },
        200,
      );
    }

    const r2Config = getR2Config();
    const idsToUpdate: string[] = [];
    const mediaToWipe: string[] = [];

    // 3. Batch extract media URLs and IDs
    for (const scan of scans) {
      idsToUpdate.push(scan.id);
      if (scan.image_storage_urls && Array.isArray(scan.image_storage_urls)) {
        mediaToWipe.push(...scan.image_storage_urls);
      }
    }

    // 4. Delete all aggregated R2 images via Cloudflare AWS protocol natively
    if (mediaToWipe.length > 0) {
      // Chunking by 500 URLs natively to protect AWS 'DeleteObjects' bounds 
      // which strictly limits to 1000 keys per HTTP execution frame.
      const urlChunkSize = 500;
      for (let i = 0; i < mediaToWipe.length; i += urlChunkSize) {
        const chunk = mediaToWipe.slice(i, i + urlChunkSize);
        await deleteR2Objects(chunk, r2Config);
      }
    }

    // 5. Zero-out the image URLs in the database (preserve row offline data)
    await zeroOutDomesticatedUrls(idsToUpdate, supabaseAdmin);

    console.log(`Purged images for ${idsToUpdate.length} domesticated scans`);

    return jsonResponse(
      { success: true, count: idsToUpdate.length },
      200,
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error(`Auto Purge Domesticated Error: ${message}`);
    return jsonResponse({ error: message }, 500);
  }
});
