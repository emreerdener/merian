import type { SupabaseClient } from "@supabase/supabase-js";
import { deleteScanMediaR2Objects, getR2Config } from "../_shared/aws.ts";
import { jsonResponse } from "../_shared/edgeHandler.ts";
import { collectScanMediaUrls } from "../_shared/scanMediaDeletion.ts";
import {
  completeScanDeletion,
  fetchScanRecord,
  requestScanDeletion,
} from "./db.ts";

export async function handleScanDeletion(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<Response> {
  // Persist the owner-bound deletion fence before touching R2. This makes a
  // lost response safely retryable and prevents delayed inference/recovery
  // from reconstructing the same UUID on another device.
  const deletion = await requestScanDeletion(
    scanId,
    userId,
    supabaseAdmin,
  );

  if (deletion === "legacy_observation_delete_requires_upgrade") {
    return jsonResponse({
      error: "Update Merian to review and delete this saved scan.",
      code: "legacy_observation_delete_requires_upgrade",
    }, 409);
  }

  if (deletion === "forbidden") {
    console.error(
      "Scan deletion denied for ownership mismatch.",
    );
    return jsonResponse(
      { error: "You do not have permission to delete this record." },
      403,
    );
  }
  if (deletion === "not_found" || deletion === "already_deleted") {
    console.log(
      "Scan deletion was already complete or absent.",
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
      await deleteScanMediaR2Objects(mediaUrls, userId, r2Config);
    }
  }

  // The owner row is removed only after every R2 delete returned 2xx/404.
  // Any failure leaves the tombstone and row available for the client's
  // persistent PendingCloudDeletionTask to resume.
  await completeScanDeletion(scanId, userId, supabaseAdmin);

  console.log("Scan deletion completed.");

  return jsonResponse({ success: true, message: "Scan deleted." }, 200);
}
