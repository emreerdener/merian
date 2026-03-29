// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { deleteR2Objects, getR2Config } from "../_shared/aws.ts";
import { corsHeaders } from "../_shared/http.ts";
import { timingSafeCompare } from "../_shared/http.ts";

import { deleteScansBulk, fetchStaleNonBioScans } from "./db.ts";

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

  // Defend against timing attacks determining API key length
  if (!timingSafeCompare(providedAuth, expectedAuth)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

    // 2. Query non-biological scans older than 30 days
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
      await deleteR2Objects(mediaToWipe, r2Config);
    }

    // 5. Purge the IDs cleanly from Postgres
    await deleteScansBulk(idsToDelete, supabaseAdmin);

    console.log(`Purged ${idsToDelete.length} stale non-biological scans`);

    return jsonResponse(
      { success: true, count: idsToDelete.length },
      200,
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error(`Auto Purge Error: ${message}`);
    return jsonResponse({ error: message }, 500);
  }
});
