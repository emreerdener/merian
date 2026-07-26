import { SupabaseClient } from "@supabase/supabase-js";

export interface ExploreMediaHealthClaim {
  media_id: string;
  post_id: string;
  user_id: string;
  kind: "image" | "video" | "audio";
  url: string;
  thumbnail_url: string | null;
  health_status: "healthy" | "suspected_missing" | "missing";
  claim_token: string;
}

export type ExploreMediaHealthOutcome =
  | "healthy"
  | "missing"
  | "retryable_error";

export interface ExploreMediaHealthRunInsert {
  started_at: string;
  finished_at: string;
  status: "success" | "partial_failure" | "failed";
  claimed_count: number;
  healthy_count: number;
  missing_observation_count: number;
  retryable_error_count: number;
  error_count: number;
  errors: Array<Record<string, unknown>>;
}

export async function claimExploreMediaHealthChecks(
  limit: number,
  leaseSeconds: number,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreMediaHealthClaim[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "claim_explore_media_health_checks",
    {
      p_limit: limit,
      p_lease_seconds: leaseSeconds,
    },
  );

  if (error) {
    throw new Error(`claimExploreMediaHealthChecks: ${error.message}`);
  }
  return (data ?? []) as ExploreMediaHealthClaim[];
}

export async function recordExploreMediaHealthCheck(
  claim: ExploreMediaHealthClaim,
  outcome: ExploreMediaHealthOutcome,
  urlHttpStatus: number | null,
  thumbnailHttpStatus: number | null,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "record_explore_media_health_check",
    {
      p_media_id: claim.media_id,
      p_claim_token: claim.claim_token,
      p_outcome: outcome,
      p_url_http_status: urlHttpStatus,
      p_thumbnail_http_status: thumbnailHttpStatus,
    },
  );

  if (error) {
    throw new Error(`recordExploreMediaHealthCheck: ${error.message}`);
  }
}

export async function recordExploreMediaHealthRun(
  run: ExploreMediaHealthRunInsert,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("explore_media_health_reconciliation_runs")
    .insert(run);
  if (error) {
    throw new Error(`recordExploreMediaHealthRun: ${error.message}`);
  }
}
