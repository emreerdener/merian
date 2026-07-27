import { deleteScanMediaR2Objects, getR2Config } from "../_shared/aws.ts";
import { serveEdge } from "../_shared/edgeHandler.ts";
import { collectScanMediaUrls } from "../_shared/scanMediaDeletion.ts";
import { corsHeaders, publicErrorResponse } from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";

import { deleteScansBulk, fetchStaleNonBioScans } from "./db.ts";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serveEdge(async (req: Request) => {
  let step = "request";

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  step = "auth";
  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAdmin = createServiceRoleClient(
      supabaseUrl,
      auth.serverApiKey,
    );

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
      mediaToWipe.push(...collectScanMediaUrls(scan));
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
    return publicErrorResponse(
      req,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
