import type { SupabaseClient } from "@supabase/supabase-js";
import {
  deleteR2Object,
  getR2Config,
  headR2Object,
  type R2Config,
  r2ObjectKeyFromPublicUrl,
} from "../_shared/aws.ts";
import { getTierForUser } from "../_shared/entitlement.ts";
import { logStructuredError } from "../_shared/edgeHandler.ts";
import { promoteSafeMedia } from "../_shared/identify/moderation.ts";
import { publicHttpError } from "../_shared/http.ts";
import {
  ownedScanImageReferenceExists,
  persistOwnedScanImageRepair,
  type ScanImageRepairCounts,
} from "./db.ts";

export type ScanImageCloudStatus =
  | "healthy"
  | "missing"
  | "not_referenced";

interface RepairWorkerDependencies {
  referenceExists?: typeof ownedScanImageReferenceExists;
  persistRepair?: typeof persistOwnedScanImageRepair;
  headObject?: typeof headR2Object;
  deleteObject?: typeof deleteR2Object;
  promoteMedia?: typeof promoteSafeMedia;
  tierForUser?: typeof getTierForUser;
  config?: () => R2Config;
}

async function checkedHeadStatus(
  objectKey: string,
  config: R2Config,
  headObject: typeof headR2Object,
): Promise<"healthy" | "missing"> {
  const response = await headObject(objectKey, config);
  const status = response.status;
  await response.body?.cancel();

  if (status >= 200 && status < 300) return "healthy";
  if (status === 404) return "missing";
  throw publicHttpError(503, "Cloud media status could not be verified.");
}

async function checkedDelete(
  objectKey: string,
  config: R2Config,
  deleteObject: typeof deleteR2Object,
): Promise<void> {
  const response = await deleteObject(objectKey, config);
  const status = response.status;
  await response.body?.cancel();
  if (status < 200 || status >= 300) {
    throw new Error(`R2 delete returned HTTP ${status}.`);
  }
}

export async function inspectOwnedScanImage(
  userId: string,
  sourceUrl: string,
  supabaseAdmin: SupabaseClient,
  dependencies: RepairWorkerDependencies = {},
): Promise<ScanImageCloudStatus> {
  const referenceExists = dependencies.referenceExists ??
    ownedScanImageReferenceExists;
  if (!await referenceExists(userId, sourceUrl, supabaseAdmin)) {
    return "not_referenced";
  }

  const objectKey = r2ObjectKeyFromPublicUrl(sourceUrl);
  if (objectKey == null) {
    throw publicHttpError(400, "Invalid durable scan image URL.");
  }

  return await checkedHeadStatus(
    objectKey,
    (dependencies.config ?? getR2Config)(),
    dependencies.headObject ?? headR2Object,
  );
}

export interface ScanImageRepairResult extends ScanImageRepairCounts {
  status: "healthy" | "repaired";
  replacementUrl: string | null;
}

export async function repairOwnedScanImage(
  userId: string,
  sourceUrl: string,
  restoredObjectKey: string,
  supabaseAdmin: SupabaseClient,
  dependencies: RepairWorkerDependencies = {},
): Promise<ScanImageRepairResult> {
  const referenceExists = dependencies.referenceExists ??
    ownedScanImageReferenceExists;
  if (!await referenceExists(userId, sourceUrl, supabaseAdmin)) {
    throw publicHttpError(404, "Owned scan image reference was not found.");
  }

  const config = (dependencies.config ?? getR2Config)();
  const headObject = dependencies.headObject ?? headR2Object;
  const sourceObjectKey = r2ObjectKeyFromPublicUrl(sourceUrl);
  if (sourceObjectKey == null) {
    throw publicHttpError(400, "Invalid durable scan image URL.");
  }

  const sourceStatus = await checkedHeadStatus(
    sourceObjectKey,
    config,
    headObject,
  );
  if (sourceStatus === "healthy") {
    try {
      await checkedDelete(
        restoredObjectKey,
        config,
        dependencies.deleteObject ?? deleteR2Object,
      );
    } catch {
      // Staging lifecycle cleanup is a safe fallback for this redundant upload.
    }
    return {
      status: "healthy",
      replacementUrl: null,
      updatedScanCount: 0,
      updatedPostMediaCount: 0,
    };
  }

  const restoredStatus = await checkedHeadStatus(
    restoredObjectKey,
    config,
    headObject,
  );
  if (restoredStatus !== "healthy") {
    throw publicHttpError(409, "The restored image upload was not found.");
  }

  const tierForUser = dependencies.tierForUser ?? getTierForUser;
  const userTier = await tierForUser(userId, supabaseAdmin);
  const promoteMedia = dependencies.promoteMedia ?? promoteSafeMedia;
  const promotedUrls = await promoteMedia({
    userId,
    r2ObjectKeys: [restoredObjectKey],
    imageBase64s: undefined,
    userTier,
    r2Config: config,
  });
  const replacementUrl = promotedUrls[0];
  if (promotedUrls.length !== 1 || replacementUrl == null) {
    throw new Error("Restored scan image promotion returned invalid state.");
  }
  const replacementObjectKey = r2ObjectKeyFromPublicUrl(replacementUrl);
  if (
    replacementObjectKey == null ||
    replacementObjectKey === sourceObjectKey ||
    (
      !replacementObjectKey.startsWith(`public_uploads/free/${userId}/`) &&
      !replacementObjectKey.startsWith(`public_uploads/pro/${userId}/`)
    )
  ) {
    throw new Error("Restored scan image promotion returned an unsafe URL.");
  }

  try {
    const counts = await (dependencies.persistRepair ??
      persistOwnedScanImageRepair)(
        userId,
        sourceUrl,
        replacementUrl,
        supabaseAdmin,
      );
    return {
      status: "repaired",
      replacementUrl,
      ...counts,
    };
  } catch (error) {
    try {
      await checkedDelete(
        replacementObjectKey,
        config,
        dependencies.deleteObject ?? deleteR2Object,
      );
    } catch (rollbackError) {
      logStructuredError("scan_image_repair_rollback_failed", {
        user_id: userId,
        replacement_url: replacementUrl,
        rollback_error: rollbackError instanceof Error
          ? rollbackError.message
          : String(rollbackError),
      });
    }
    throw error;
  }
}
