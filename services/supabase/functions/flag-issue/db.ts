import { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../_shared/http.ts";

export type OwnedFlagIssueResult = "submitted" | "not_found" | "not_owner";

interface CommunityRequestRow {
  id?: unknown;
  post_id?: unknown;
}

interface CommunityIdentificationDetailRow {
  post_id?: unknown;
  scan_id?: unknown;
}

export interface LegacyCommunityPostReportTarget {
  postId: string;
}

export function isLegacyCommunityPostReport(
  flagReason: string,
  userSuggestion: string | undefined,
): boolean {
  return flagReason === "Inappropriate content" &&
    userSuggestion === "Reported from Community request";
}

export async function submitOwnedFlagIssue(
  scanId: string,
  reporterUserId: string,
  flagReason: string,
  userSuggestion: string | undefined,
  supabaseAdmin: SupabaseClient,
): Promise<OwnedFlagIssueResult> {
  const { data, error } = await supabaseAdmin.rpc("submit_owned_flag_issue", {
    p_scan_id: scanId,
    p_reporter_user_id: reporterUserId,
    p_flag_reason: flagReason,
    p_user_suggestion: userSuggestion ?? null,
  });
  if (error) {
    throw new Error(`Failed to submit flagged review: ${error.message}`);
  }

  if (data === "submitted" || data === "not_found" || data === "not_owner") {
    return data;
  }
  throw new Error("Flagged review returned an invalid result.");
}

export async function resolveLegacyCommunityPostReport(
  scanId: string,
  reporterUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<LegacyCommunityPostReportTarget> {
  const { data, error } = await supabaseAdmin
    .from("explore_community_requests")
    .select("id,post_id")
    .eq("scan_id", scanId)
    .is("withdrawn_at", null)
    .maybeSingle();
  if (error) {
    throw new Error(
      `Failed to resolve legacy Community post report: ${error.message}`,
    );
  }

  const request = data as CommunityRequestRow | null;
  if (
    typeof request?.id !== "string" || typeof request.post_id !== "string"
  ) {
    throw publicHttpError(404, "Scan is not available for reporting.");
  }

  const { data: detailData, error: detailError } = await supabaseAdmin.rpc(
    "get_community_identification_detail",
    {
      self_id: reporterUserId,
      target_request_id: request.id,
    },
  );
  if (detailError) {
    throw new Error(
      `Failed to authorize legacy Community post report: ${detailError.message}`,
    );
  }

  const detail = Array.isArray(detailData)
    ? detailData[0] as CommunityIdentificationDetailRow | undefined
    : undefined;
  if (
    typeof detail?.scan_id !== "string" ||
    detail.scan_id.toLowerCase() !== scanId.toLowerCase() ||
    typeof detail.post_id !== "string" ||
    detail.post_id.toLowerCase() !== request.post_id.toLowerCase()
  ) {
    throw publicHttpError(404, "Scan is not available for reporting.");
  }

  return { postId: request.post_id };
}
