import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { deleteScanMediaR2Objects, getR2Config } from "../_shared/aws.ts";
import { corsHeaders } from "../_shared/http.ts";
import { timingSafeCompare } from "../_shared/http.ts";

import { deleteScansBulk, fetchStaleNonBioScans } from "./db.ts";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  let step = "request";

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  // 1. Authenticate the Webhook via Service Role Key natively
  step = "auth";
  const expectedAuth = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  const providedAuth = req.headers.get("Authorization") ?? "";

  // Defend against timing attacks determining API key length
  if (!timingSafeCompare(providedAuth, expectedAuth)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

    // 2. Query non-biological scans older than 30 days
    step = "fetch_stale_nonbio_scans";
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const boundaryIso = thirtyDaysAgo.toISOString();

    const scans = await fetchStaleNonBioScans(boundaryIso, supabaseAdmin);

    if (scans.length === 0) {
      return jsonResponse(
        { message: "No non-biological scans to purge." },
        200,
      );
    }

    const r2Config = getR2Config();
    const idsToDelete: string[] = [];
    const mediaToWipe: string[] = [];

    // 3. Batch extract media URLs and IDs
    for (const scan of scans) {
      idsToDelete.push(scan.id);
      if (scan.image_storage_urls && Array.isArray(scan.image_storage_urls)) {
        mediaToWipe.push(...scan.image_storage_urls);
      }
    }

    // 4. Delete all aggregated R2 images via Cloudflare AWS protocol natively
    if (mediaToWipe.length > 0) {
      step = "delete_r2_objects";
      await deleteScanMediaR2Objects(mediaToWipe, r2Config);
    }

    // 5. Purge the IDs cleanly from Postgres
    step = "delete_scan_rows";
    await deleteScansBulk(idsToDelete, supabaseAdmin);

    console.log(JSON.stringify({
      event: "auto_purge_nonbio_complete",
      scan_count: idsToDelete.length,
      media_count: mediaToWipe.length,
    }));

    return jsonResponse(
      { success: true, count: idsToDelete.length },
      200,
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error(JSON.stringify({
      event: "auto_purge_nonbio_failed",
      step,
      error: message,
    }));
    return jsonResponse({ error: message, step }, 500);
  }
});
