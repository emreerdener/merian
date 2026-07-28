import { type SupabaseClient } from "@supabase/supabase-js";
import { UUID_RE } from "./explore.ts";
import { publicHttpError } from "./http.ts";
import {
  fetchScanIngestionJob,
  type ScanIngestionJobRow,
} from "./scanIngestionJobs.ts";

export interface OwnedScanRecoveryRow {
  id: string;
  user_id: string;
  species_id: string | null;
  confirmed_species_id: string | null;
  image_storage_urls: string[];
  timestamp: string;
  gps_lat_exact: number | null;
  gps_long_exact: number | null;
  gps_lat_public: number | null;
  gps_long_public: number | null;
  gps_elevation: number | null;
  geoprivacy: "open" | "obscured" | "private";
  weather_condition: string | null;
  weather_temperature_f: number | null;
  ai_confidence_score: number;
  ecology_type: "wild" | "urban" | "domesticated" | "unknown";
  is_invasive: boolean;
  invasive_status_region: string | null;
  invasive_rationale: string | null;
  invasive_confidence: number | null;
  is_live_capture: boolean;
  is_biological_subject: boolean;
  ai_reasoning: string | null;
  semantic_location: string | null;
  public_location_label: string | null;
  inference_tier: string;
  image_quality_score: number | null;
  user_identification_override: string | null;
  user_confirmed_identification: boolean;
  user_review_state: "unreviewed" | "ai_confirmed" | "user_overridden";
}

function badRecovery(message: string): never {
  throw publicHttpError(400, `recovery_scan ${message}`);
}

function requiredString(
  record: Record<string, unknown>,
  key: string,
  maximumLength: number,
): string {
  const value = record[key];
  if (typeof value !== "string") {
    return badRecovery(`${key} must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > maximumLength) {
    return badRecovery(
      `${key} must be between 1 and ${maximumLength} characters.`,
    );
  }
  return trimmed;
}

function optionalString(
  record: Record<string, unknown>,
  key: string,
  maximumLength: number,
): string | null {
  const value = record[key];
  if (value == null) return null;
  if (typeof value !== "string") {
    return badRecovery(`${key} must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > maximumLength) {
    return badRecovery(`${key} must be ${maximumLength} characters or fewer.`);
  }
  return trimmed;
}

function optionalUuid(
  record: Record<string, unknown>,
  key: string,
): string | null {
  const value = record[key];
  if (value == null) return null;
  if (typeof value !== "string" || !UUID_RE.test(value.trim())) {
    return badRecovery(`${key} must be a valid UUID.`);
  }
  return value.trim().toLowerCase();
}

function requiredBoolean(
  record: Record<string, unknown>,
  key: string,
): boolean {
  const value = record[key];
  if (typeof value !== "boolean") {
    return badRecovery(`${key} must be a boolean.`);
  }
  return value;
}

function numberInRange(
  record: Record<string, unknown>,
  key: string,
  minimum: number,
  maximum: number,
  required = false,
): number | null {
  const value = record[key];
  if (value == null && !required) return null;
  if (
    typeof value !== "number" || !Number.isFinite(value) ||
    value < minimum || value > maximum
  ) {
    return badRecovery(`${key} must be between ${minimum} and ${maximum}.`);
  }
  return value;
}

function enumValue<T extends string>(
  record: Record<string, unknown>,
  key: string,
  allowed: readonly T[],
): T {
  const value = record[key];
  if (typeof value !== "string" || !allowed.includes(value as T)) {
    return badRecovery(`${key} is invalid.`);
  }
  return value as T;
}

/**
 * Accepts only the durable, non-media scan fields needed to reconstruct an
 * owner's missing cloud row. Identity and public location are derived here,
 * while media must still arrive through validated owner staging keys.
 */
export function normalizeOwnedScanRecovery(
  value: unknown,
  scanId: string,
  userId: string,
): OwnedScanRecoveryRow | null {
  if (value == null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    return badRecovery("must be an object.");
  }

  const record = value as Record<string, unknown>;
  const payloadScanId = requiredString(record, "id", 36).toLowerCase();
  const payloadUserId = requiredString(record, "user_id", 36).toLowerCase();
  if (!UUID_RE.test(payloadScanId)) {
    return badRecovery("id must be a valid UUID.");
  }
  if (!UUID_RE.test(payloadUserId)) {
    return badRecovery("user_id must be a valid UUID.");
  }
  if (payloadScanId !== scanId.toLowerCase()) {
    return badRecovery("id must match scan_id.");
  }
  if (payloadUserId !== userId.toLowerCase()) {
    return badRecovery("user_id must belong to the current user.");
  }

  const rawTimestamp = requiredString(record, "timestamp", 64);
  const timestampMs = Date.parse(rawTimestamp);
  if (!Number.isFinite(timestampMs)) {
    return badRecovery("timestamp must be a valid ISO 8601 date.");
  }

  if (
    !Array.isArray(record.image_storage_urls) ||
    record.image_storage_urls.length !== 0
  ) {
    return badRecovery(
      "image_storage_urls must be empty; restore media through staging keys.",
    );
  }

  const geoprivacy = enumValue(
    record,
    "geoprivacy",
    ["open", "obscured", "private"] as const,
  );
  const gpsLatExact = numberInRange(
    record,
    "gps_lat_exact",
    -90,
    90,
  );
  const gpsLongExact = numberInRange(
    record,
    "gps_long_exact",
    -180,
    180,
  );
  if ((gpsLatExact == null) !== (gpsLongExact == null)) {
    return badRecovery(
      "gps_lat_exact and gps_long_exact must be provided together.",
    );
  }
  const publicLocationLabel = geoprivacy === "private"
    ? null
    : optionalString(record, "public_location_label", 500);

  const imageQualityScore = numberInRange(
    record,
    "image_quality_score",
    0,
    100,
  );
  if (imageQualityScore != null && !Number.isInteger(imageQualityScore)) {
    return badRecovery("image_quality_score must be an integer.");
  }

  return {
    id: scanId.toLowerCase(),
    user_id: userId.toLowerCase(),
    species_id: optionalUuid(record, "species_id"),
    confirmed_species_id: optionalUuid(record, "confirmed_species_id"),
    image_storage_urls: [],
    timestamp: new Date(timestampMs).toISOString(),
    gps_lat_exact: gpsLatExact,
    gps_long_exact: gpsLongExact,
    gps_lat_public: geoprivacy === "open" ? gpsLatExact : null,
    gps_long_public: geoprivacy === "open" ? gpsLongExact : null,
    gps_elevation: numberInRange(record, "gps_elevation", -500, 9500),
    geoprivacy,
    weather_condition: optionalString(record, "weather_condition", 200),
    weather_temperature_f: numberInRange(
      record,
      "weather_temperature_f",
      -200,
      200,
    ),
    ai_confidence_score: numberInRange(
      record,
      "ai_confidence_score",
      0,
      1,
      true,
    )!,
    ecology_type: enumValue(
      record,
      "ecology_type",
      ["wild", "urban", "domesticated", "unknown"] as const,
    ),
    is_invasive: requiredBoolean(record, "is_invasive"),
    invasive_status_region: optionalString(
      record,
      "invasive_status_region",
      500,
    ),
    invasive_rationale: optionalString(record, "invasive_rationale", 2_000),
    invasive_confidence: numberInRange(
      record,
      "invasive_confidence",
      0,
      1,
    ),
    is_live_capture: requiredBoolean(record, "is_live_capture"),
    is_biological_subject: requiredBoolean(
      record,
      "is_biological_subject",
    ),
    ai_reasoning: optionalString(record, "ai_reasoning", 10_000),
    semantic_location: optionalString(record, "semantic_location", 1_000),
    public_location_label: publicLocationLabel,
    inference_tier: requiredString(record, "inference_tier", 64),
    image_quality_score: imageQualityScore,
    user_identification_override: optionalString(
      record,
      "user_identification_override",
      500,
    ),
    user_confirmed_identification: requiredBoolean(
      record,
      "user_confirmed_identification",
    ),
    user_review_state: enumValue(
      record,
      "user_review_state",
      ["unreviewed", "ai_confirmed", "user_overridden"] as const,
    ),
  };
}

/**
 * Recreates only a missing owner row. A raced insert or an id collision remains
 * untouched and must be resolved by reloading with both id and owner filters.
 * Recovery also defers to richer active/retryable ingestion and never bypasses
 * a terminal moderation rejection.
 */
export async function recoverMissingOwnedScan(
  recoveryScan: OwnedScanRecoveryRow,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const ingestionJob = await fetchScanIngestionJob(
    recoveryScan.id,
    recoveryScan.user_id,
    supabaseAdmin,
  );
  if (!scanIngestionJobAllowsRecovery(ingestionJob)) {
    return false;
  }

  const { error } = await supabaseAdmin
    .from("scans")
    .upsert(recoveryScan, {
      onConflict: "id",
      ignoreDuplicates: true,
    });

  if (error) {
    throw new Error(`Failed to recover missing scan: ${error.message}`);
  }

  return true;
}

export function scanIngestionJobAllowsRecovery(
  job: ScanIngestionJobRow | null | undefined,
): boolean {
  if (!job) return true;
  const normalizedStage = job.stage.trim().toLowerCase();
  const normalizedError = job.last_error?.trim().toLowerCase() ?? "";
  const isModerationRejection = normalizedStage === "moderation_rejected" &&
    (
      normalizedError === "multimodal media rejected by moderation." ||
      normalizedError === "media rejected by moderation."
    );
  const isProviderPolicyRejection =
    normalizedStage === "ai_inference_non_stop_finish" &&
    (
      normalizedError === "ai finish reason: safety" ||
      normalizedError === "ai finish reason: prohibited_content"
    );
  if (isModerationRejection || isProviderPolicyRejection) return false;
  return job.status === "complete" || job.status === "failed_terminal";
}
