import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export const DEFAULT_QUALITY_THRESHOLD = 90;
export const DEFAULT_PER_SPECIES_LIMIT = 8;
export const MAX_PER_SPECIES_LIMIT = 50;

export interface MerianReferenceImageRefreshRequest {
  qualityThreshold: number;
  perSpeciesLimit: number;
  dryRun: boolean;
}

export interface MerianReferenceImageRefreshRequestResult {
  request?: MerianReferenceImageRefreshRequest;
  error?: string;
  status?: number;
}

export interface MerianReferenceImageRefreshResult {
  candidate_count: number;
  promoted_count: number;
  removed_count: number;
  species_count: number;
  dry_run: boolean;
}

export function parseMerianReferenceImageRefreshRequest(
  body: Record<string, unknown> = {},
): MerianReferenceImageRefreshRequestResult {
  const qualityResult = parseQualityThreshold(
    body.quality_threshold ?? body.qualityThreshold,
  );
  if (qualityResult.error) return qualityResult;

  const perSpeciesResult = parsePerSpeciesLimit(
    body.per_species_limit ?? body.perSpeciesLimit,
  );
  if (perSpeciesResult.error) return perSpeciesResult;

  const dryRunResult = parseDryRun(body.dry_run ?? body.dryRun);
  if (dryRunResult.error) return dryRunResult;

  return {
    request: {
      qualityThreshold: qualityResult.qualityThreshold ??
        DEFAULT_QUALITY_THRESHOLD,
      perSpeciesLimit: perSpeciesResult.perSpeciesLimit ??
        DEFAULT_PER_SPECIES_LIMIT,
      dryRun: dryRunResult.dryRun ?? false,
    },
  };
}

export async function runMerianReferenceImageRefresh(
  request: MerianReferenceImageRefreshRequest,
  supabaseAdmin: SupabaseClient,
): Promise<MerianReferenceImageRefreshResult> {
  const { data, error } = await supabaseAdmin.rpc(
    "refresh_merian_reference_images",
    {
      p_quality_threshold: request.qualityThreshold,
      p_per_species_limit: request.perSpeciesLimit,
      p_dry_run: request.dryRun,
    },
  );
  if (error) {
    throw new Error(
      `refresh_merian_reference_images failed: ${error.message}`,
    );
  }

  const row = Array.isArray(data) ? data[0] : data;
  return normalizeRefreshResult(row, request.dryRun);
}

function normalizeRefreshResult(
  row: unknown,
  dryRun: boolean,
): MerianReferenceImageRefreshResult {
  if (!row || typeof row !== "object") {
    return {
      candidate_count: 0,
      promoted_count: 0,
      removed_count: 0,
      species_count: 0,
      dry_run: dryRun,
    };
  }

  const value = row as Record<string, unknown>;
  return {
    candidate_count: integerValue(value.candidate_count),
    promoted_count: integerValue(value.promoted_count),
    removed_count: integerValue(value.removed_count),
    species_count: integerValue(value.species_count),
    dry_run: value.dry_run === true,
  };
}

function parseQualityThreshold(
  value: unknown,
): MerianReferenceImageRefreshRequestResult & {
  qualityThreshold?: number;
} {
  if (value === undefined || value === null) {
    return { qualityThreshold: DEFAULT_QUALITY_THRESHOLD };
  }
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 0 ||
    value > 100
  ) {
    return {
      error: "quality_threshold must be an integer from 0 to 100.",
      status: 400,
    };
  }
  return { qualityThreshold: value };
}

function parsePerSpeciesLimit(
  value: unknown,
): MerianReferenceImageRefreshRequestResult & {
  perSpeciesLimit?: number;
} {
  if (value === undefined || value === null) {
    return { perSpeciesLimit: DEFAULT_PER_SPECIES_LIMIT };
  }
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 1 ||
    value > MAX_PER_SPECIES_LIMIT
  ) {
    return {
      error:
        `per_species_limit must be an integer from 1 to ${MAX_PER_SPECIES_LIMIT}.`,
      status: 400,
    };
  }
  return { perSpeciesLimit: value };
}

function parseDryRun(
  value: unknown,
): MerianReferenceImageRefreshRequestResult & { dryRun?: boolean } {
  if (value === undefined || value === null) return { dryRun: false };
  if (typeof value !== "boolean") {
    return { error: "dry_run must be a boolean.", status: 400 };
  }
  return { dryRun: value };
}

function integerValue(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) ? value : 0;
}
