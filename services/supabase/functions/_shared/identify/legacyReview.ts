import type { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../http.ts";

/** Fail before quota/GBIF work; the commit RPC repeats this under its locks. */
export async function requireLegacyReview(
  admin: SupabaseClient,
  userID: string,
  scanID: string,
  notFoundCode = "identification_review_not_found",
): Promise<void> {
  const { error } = await admin.rpc("require_legacy_scan_review", {
    p_user_id: userID,
    p_scan_id: scanID,
  });
  if (error) {
    throwIfAnalysisBoundReview(error.message);
    if (error.message === "identification_review_not_found") {
      throw publicHttpError(
        404,
        "This observation is unavailable.",
        notFoundCode,
      );
    }
    throw new Error("Identification review admission failed.");
  }
}

export function throwIfAnalysisBoundReview(message: string): void {
  if (message === "analysis_bound_review_required") {
    throw publicHttpError(
      409,
      "Review this identification from its observation history.",
      "analysis_bound_review_required",
    );
  }
}
