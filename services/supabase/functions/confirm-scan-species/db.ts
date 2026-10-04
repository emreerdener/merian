export { admitReview } from "../_shared/identify/speciesVerification.ts";
import {
  requireLegacyReview,
  throwIfAnalysisBoundReview,
} from "../_shared/identify/legacyReview.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../_shared/http.ts";
import {
  parsePrimaryIdentification,
  type PrimaryIdentification,
} from "../_shared/identify/contract.ts";
import type { VerifiedLookalikeTaxon } from "../_shared/verifiedSpecies.ts";
import {
  parseReviewReceipt,
  type ReviewReceipt,
  type ReviewRequest,
} from "./contract.ts";

export interface OwnedReviewTarget {
  primary: PrimaryIdentification;
  revision: number;
}
export async function findReviewTarget(
  admin: SupabaseClient,
  userID: string,
  scanID: string,
): Promise<OwnedReviewTarget> {
  await requireLegacyReview(admin, userID, scanID, "species_review_not_found");
  const { data, error } = await admin.from("scans")
    .select(
      "primary_identification, identification_provenance, confirmed_species_identity_revision",
    )
    .eq("id", scanID).eq("user_id", userID).eq("is_tombstoned", false).limit(1)
    .maybeSingle();
  if (error) throw new Error("Species review lookup failed.");
  if (!data) {
    throw publicHttpError(
      404,
      "This observation is unavailable.",
      "species_review_not_found",
    );
  }
  if (data.primary_identification === null) {
    throw publicHttpError(
      409,
      "This observation uses the earlier review format.",
      "species_review_requires_primary",
    );
  }
  if (
    data.identification_provenance?.schema !== "merian_identify_primary_v1" ||
    !Number.isInteger(data.confirmed_species_identity_revision) ||
    data.confirmed_species_identity_revision < 0 ||
    data.confirmed_species_identity_revision > 2147483647
  ) throw new Error("Species review state is invalid.");
  return {
    primary: parsePrimaryIdentification(data.primary_identification),
    revision: data.confirmed_species_identity_revision,
  };
}
export async function applyReview(
  admin: SupabaseClient,
  userID: string,
  request: ReviewRequest,
  name: string | null,
  taxon: VerifiedLookalikeTaxon | null,
): Promise<ReviewReceipt> {
  const { data, error } = await admin.rpc(
    "apply_verified_scan_species_review",
    {
      p_user_id: userID,
      p_scan_id: request.scan_id,
      p_expected_revision: request.expected_revision,
      p_action: request.action,
      p_requested_name: name,
      p_taxon: taxon,
    },
  );
  if (error) {
    throwIfAnalysisBoundReview(error.message);
    switch (error.message) {
      case "identification_review_not_found":
      case "species_review_not_found":
        throw publicHttpError(
          404,
          "This observation is unavailable.",
          "species_review_not_found",
        );
      case "species_review_revision_conflict":
        throw publicHttpError(
          409,
          "This review changed. Refresh the observation before trying again.",
          "species_review_revision_conflict",
        );
      case "species_review_requires_primary":
        throw publicHttpError(
          409,
          "This observation uses the earlier review format.",
          "species_review_requires_primary",
        );
      case "species_review_primary_not_species":
      case "invalid_verified_species":
        throw publicHttpError(
          422,
          "This selection could not be verified as a species.",
          "species_not_verified",
        );
      case "species_resolution_identity_conflict":
      case "species_resolution_ambiguous_identity":
        throw publicHttpError(
          422,
          "This species is unavailable for confirmation.",
          "species_not_verified",
        );
      default:
        throw new Error("Species review persistence failed.");
    }
  }
  return parseReviewReceipt(data, request.scan_id);
}
