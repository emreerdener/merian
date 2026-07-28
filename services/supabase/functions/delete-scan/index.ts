import { deleteScanMediaR2Objects, getR2Config } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { collectScanMediaUrls } from "../_shared/scanMediaDeletion.ts";

import {
  completeScanDeletion,
  fetchScanRecord,
  requestScanDeletion,
} from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const requestBody = await parseJsonBody(req, { limit: "small" });
    if (requestBody instanceof Response) return requestBody;

    const paramErr = requireParams(requestBody, ["scanId"]);
    if (paramErr) return paramErr;

    const { scanId } = requestBody;

    const UUID_RE =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (typeof scanId !== "string" || !UUID_RE.test(scanId)) {
      return jsonResponse({ error: "scanId must be a valid UUID." }, 400);
    }

    // Persist the owner-bound deletion fence before touching R2. This makes a
    // lost response safely retryable and prevents delayed inference/recovery
    // from reconstructing the same UUID on another device.
    const deletion = await requestScanDeletion(
      scanId,
      user.id,
      supabaseAdmin,
    );

    if (deletion === "forbidden") {
      console.error(
        `IDOR attempt: User ${user.id} tried to delete scan ${scanId}`,
      );
      return jsonResponse(
        { error: "You do not have permission to delete this record." },
        403,
      );
    }
    if (deletion === "not_found" || deletion === "already_deleted") {
      console.log(
        `Scan ${scanId} was already absent for user ${user.id}.`,
      );
      return jsonResponse(
        { success: true, message: "Scan already deleted." },
        200,
      );
    }

    // The durable fence blocks all later scan mutation, so this post-fence
    // media snapshot cannot miss a concurrently appended canonical object.
    const scan = await fetchScanRecord(scanId, supabaseAdmin);

    if (scan) {
      const mediaUrls = collectScanMediaUrls(scan);
      if (mediaUrls.length > 0) {
        const r2Config = getR2Config();
        await deleteScanMediaR2Objects(mediaUrls, user.id, r2Config);
      }
    }

    // The owner row is removed only after every R2 delete returned 2xx/404.
    // Any failure leaves the tombstone and row available for the client's
    // persistent PendingCloudDeletionTask to resume.
    await completeScanDeletion(scanId, user.id, supabaseAdmin);

    console.log(`Deleted scan ${scanId} for user ${user.id}`);

    return jsonResponse({ success: true, message: "Scan deleted." }, 200);
  })
);
