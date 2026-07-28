import type { SupabaseClient } from "@supabase/supabase-js";

export interface ScanImageRepairCounts {
  updatedScanCount: number;
  updatedPostMediaCount: number;
}

type ScanImageRepairWriteOutcome =
  | "reported_success"
  | "reported_rejected"
  | "unknown";

type ScanImageRepairPersistenceResolution =
  | "committed"
  | "rejected"
  | "unknown";

export class ScanImageRepairPersistenceOutcomeUnknownError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ScanImageRepairPersistenceOutcomeUnknownError";
  }
}

export function isScanImageRepairPersistenceOutcomeUnknown(
  error: unknown,
): error is ScanImageRepairPersistenceOutcomeUnknownError {
  return error instanceof ScanImageRepairPersistenceOutcomeUnknownError;
}

export function resolveScanImageRepairPersistence(
  writeOutcome: ScanImageRepairWriteOutcome,
  sourceStillReferenced: boolean,
  replacementReferenced: boolean,
): ScanImageRepairPersistenceResolution {
  if (!sourceStillReferenced && replacementReferenced) return "committed";

  // Deleting the promoted replacement is safe only when the database itself
  // returned a rejection, the old URL remains authoritative, and no owned scan
  // references the replacement. Every other topology can be a lost commit,
  // concurrent repair, or concurrent lifecycle transition.
  if (
    writeOutcome === "reported_rejected" &&
    sourceStillReferenced &&
    !replacementReferenced
  ) {
    return "rejected";
  }
  return "unknown";
}

export async function ownedScanImageReferenceExists(
  userId: string,
  sourceUrl: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from("scans")
    .select("id")
    .eq("user_id", userId)
    .eq("is_tombstoned", false)
    .contains("image_storage_urls", [sourceUrl])
    .limit(1);

  if (error) {
    throw new Error(`Could not inspect owned scan media: ${error.message}`);
  }

  return (data?.length ?? 0) > 0;
}

export async function persistOwnedScanImageRepair(
  userId: string,
  sourceUrl: string,
  replacementUrl: string,
  supabaseAdmin: SupabaseClient,
): Promise<ScanImageRepairCounts> {
  let writeOutcome: ScanImageRepairWriteOutcome = "unknown";
  let data: unknown = null;
  let writeFailure = "scan image repair response was lost";

  try {
    const result = await supabaseAdmin.rpc(
      "repair_owned_scan_image_reference",
      {
        p_user_id: userId,
        p_source_url: sourceUrl,
        p_replacement_url: replacementUrl,
      },
    );
    data = result.data;
    if (result.error) {
      writeOutcome = "reported_rejected";
      writeFailure = result.error.message;
    } else {
      writeOutcome = "reported_success";
    }
  } catch (error) {
    writeFailure = error instanceof Error ? error.message : String(error);
  }

  if (
    writeOutcome === "reported_success" &&
    data != null &&
    typeof data === "object" &&
    !Array.isArray(data)
  ) {
    const row = data as Record<string, unknown>;
    if (
      Number.isInteger(row.updated_scan_count) &&
      (row.updated_scan_count as number) >= 0 &&
      Number.isInteger(row.updated_post_media_count) &&
      (row.updated_post_media_count as number) >= 0
    ) {
      return {
        updatedScanCount: row.updated_scan_count as number,
        updatedPostMediaCount: row.updated_post_media_count as number,
      };
    }
    writeFailure = "scan image repair returned invalid state";
  }

  let sourceStillReferenced: boolean;
  let replacementReferenced: boolean;
  try {
    sourceStillReferenced = await ownedScanImageReferenceExists(
      userId,
      sourceUrl,
      supabaseAdmin,
    );
    replacementReferenced = await ownedScanImageReferenceExists(
      userId,
      replacementUrl,
      supabaseAdmin,
    );
  } catch (error) {
    throw new ScanImageRepairPersistenceOutcomeUnknownError(
      `Could not verify scan image repair persistence: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }

  const resolution = resolveScanImageRepairPersistence(
    writeOutcome,
    sourceStillReferenced,
    replacementReferenced,
  );
  if (resolution === "committed") {
    return {
      // Counts are response metadata only. One exact active owner reference is
      // enough to prove the atomic RPC committed when its response was lost.
      updatedScanCount: 1,
      updatedPostMediaCount: 0,
    };
  }
  if (resolution === "rejected") {
    throw new Error(`Could not persist scan image repair: ${writeFailure}`);
  }
  throw new ScanImageRepairPersistenceOutcomeUnknownError(
    `Could not confirm scan image repair persistence: ${writeFailure}`,
  );
}
