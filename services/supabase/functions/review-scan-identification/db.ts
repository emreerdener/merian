import {
  requireLegacyReview,
  throwIfAnalysisBoundReview,
} from "../_shared/identify/legacyReview.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../_shared/http.ts";
import { parseAIIdentificationReview } from "../_shared/identify/aiIdentificationReview.ts";
import { parsePrimaryIdentification } from "../_shared/identify/contract.ts";
import type { VerifiedLookalikeTaxon } from "../_shared/verifiedSpecies.ts";
import { parseReceipt, type ReviewRequest } from "./contract.ts";
export async function findTarget(
  admin: SupabaseClient,
  userID: string,
  scanID: string,
) {
  await requireLegacyReview(admin, userID, scanID);
  const { data, error } = await admin.from("scans").select(
    "ai_identification_review, primary_identification, confirmed_species_identity_revision, species:species_dictionary!scans_species_id_fkey(scientific_name)",
  )
    .eq("id", scanID).eq("user_id", userID).eq("is_tombstoned", false).limit(1)
    .maybeSingle();
  if (error) throw new Error("Identification review lookup failed.");
  if (!data) {
    throw publicHttpError(
      404,
      "This observation is unavailable.",
      "identification_review_not_found",
    );
  }
  const review = data.ai_identification_review == null
    ? null
    : parseAIIdentificationReview(data.ai_identification_review);
  const primary = data.primary_identification == null
    ? null
    : parsePrimaryIdentification(data.primary_identification);
  const species = data.species as unknown as
    | { scientific_name?: string }
    | null;
  return {
    revision: review?.revision ?? 0,
    primary,
    name: primary ? primary.scientific_name : species?.scientific_name ?? null,
  };
}
export async function applyReview(
  admin: SupabaseClient,
  userID: string,
  request: ReviewRequest,
  name: string | null,
  taxon: VerifiedLookalikeTaxon | null,
) {
  const { data, error } = await admin.rpc("apply_scan_identification_review", {
    p_user_id: userID,
    p_source_scan_id: request.source_scan_id,
    p_source_revision: request.source_revision,
    p_scan_id: request.scan_id,
    p_expected_revision: request.expected_revision,
    p_operation_id: request.operation_id,
    p_action: request.action,
    p_requested_name: name,
    p_taxon: taxon,
    p_species_review_revision: request.expected_species_review_revision,
  });
  if (error) {
    throwIfAnalysisBoundReview(error.message);
    if (
      [
        "identification_review_revision_conflict",
        "species_review_revision_conflict",
      ].includes(error.message)
    ) {
      throw publicHttpError(
        409,
        "This identification changed. Review the latest decision.",
        "identification_review_revision_conflict",
      );
    }
    if (error.message === "identification_review_not_found") {
      throw publicHttpError(
        404,
        "This observation is unavailable.",
        "identification_review_not_found",
      );
    }
    if (error.message === "invalid_identification_review") {
      throw publicHttpError(
        400,
        "This review is unavailable for this observation.",
        "invalid_identification_review",
      );
    }
    throw new Error("Identification review persistence failed.");
  }
  return parseReceipt(data, request.scan_id);
}
