import { deleteScanMediaR2Objects, getR2Config } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { collectScanMediaUrls } from "../_shared/scanMediaDeletion.ts";

import { deleteScanRecord, fetchScanRecord } from "./db.ts";

Deno.serve((req: Request) =>
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

    const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (typeof scanId !== "string" || !UUID_RE.test(scanId)) {
      return jsonResponse({ error: "scanId must be a valid UUID." }, 400);
    }

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

    // 3. Delete scan media from Cloudflare R2 native
    const mediaUrls = collectScanMediaUrls(scan);
    if (mediaUrls.length > 0) {
      const r2Config = getR2Config();
      await deleteScanMediaR2Objects(mediaUrls, r2Config);
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
