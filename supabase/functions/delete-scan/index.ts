// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { deleteR2Objects, getR2Config } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";

import { deleteScanRecord, fetchScanRecord } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let requestBody;
    try {
      requestBody = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(requestBody, ["scanId"]);
    if (paramErr) return paramErr;
    
    const { scanId } = requestBody;

    // 1. Fetch the scan record
    const scan = await fetchScanRecord(scanId, supabaseAdmin);

    // If the scan doesn't exist remotely, treat as success — offline sync will drop it cleanly.
    if (!scan) {
      console.log(
        `Scan ${scanId} not found remotely; skipping for offline sync.`,
      );
      return jsonResponse(
        { success: true, message: "Scan not found remotely." },
        200,
      );
    }

    // 2. Verify ownership before deletion (IDOR protection)
    if (scan.user_id !== user.id) {
      console.error(
        `IDOR attempt: User ${user.id} tried to delete scan ${scanId} owned by ${scan.user_id}`,
      );
      return jsonResponse(
        { error: "Forbidden: You do not have permission to delete this record." },
        403,
        // Using explicit 403 to indicate malicious tracking, not just 404
      );
    }

    // 3. Delete images from Cloudflare R2 native
    if (scan.image_storage_urls && Array.isArray(scan.image_storage_urls)) {
      const r2Config = getR2Config();
      await deleteR2Objects(scan.image_storage_urls, r2Config);
    }

    // 4. Execute cascading scan database deletion
    try {
      await deleteScanRecord(scanId, supabaseAdmin);
    } catch (dbError: unknown) {
      const err = dbError as Error;
      console.error(err.message);
      return jsonResponse(
        { error: "Internal Server Error: Failed to delete scan record." },
        500,
      );
    }

    console.log(`Deleted scan ${scanId} for user ${user.id}`);

    return jsonResponse({ success: true, message: "Scan deleted." }, 200);
  }),
);
