import type { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../_shared/http.ts";
import {
  type AnalysisConfirmationRequest,
  parseConfirmationPreparation,
} from "../_shared/analysisHistory/confirmation.ts";
import type { VerifiedLookalikeTaxon } from "../_shared/verifiedSpecies.ts";

function persistenceError(message: string): never {
  switch (message) {
    case "analysis_history_not_found":
      throw publicHttpError(
        404,
        "This identification is unavailable.",
        message,
      );
    case "analysis_history_operation_conflict":
      throw publicHttpError(
        409,
        "This operation has a different saved intent.",
        message,
      );
    case "species_review_requires_primary":
      throw publicHttpError(
        409,
        "This identification uses the earlier review format.",
        message,
      );
    case "invalid_analysis_history":
      throw publicHttpError(400, "Invalid identification review.", message);
    case "invalid_identification_review":
    case "species_review_primary_not_species":
    case "invalid_verified_species":
    case "species_resolution_identity_conflict":
    case "species_resolution_ambiguous_identity":
      throw publicHttpError(
        422,
        "This identification cannot be confirmed.",
        "species_not_verified",
      );
    default:
      throw publicHttpError(
        503,
        "Identification review is temporarily unavailable.",
        "analysis_history_unavailable",
      );
  }
}

export async function prepareConfirmation(
  admin: SupabaseClient,
  userID: string,
  request: AnalysisConfirmationRequest,
) {
  const { data, error } = await admin.rpc(
    "prepare_observation_analysis_confirmation",
    {
      p_user_id: userID,
      p_request: request,
      p_reader: 10,
    },
  );
  if (error) persistenceError(error.message);
  return parseConfirmationPreparation(data, request);
}

export async function completeConfirmation(
  admin: SupabaseClient,
  userID: string,
  request: AnalysisConfirmationRequest,
  name: string,
  taxon: VerifiedLookalikeTaxon | null,
) {
  const { data, error } = await admin.rpc(
    "complete_observation_analysis_confirmation",
    {
      p_user_id: userID,
      p_request: request,
      p_reader: 10,
      p_verified_name: name,
      p_taxon: taxon,
    },
  );
  if (error) persistenceError(error.message);
  const result = parseConfirmationPreparation(data, request);
  if (result.status !== "complete") {
    throw new Error("Invalid confirmation completion.");
  }
  return result.receipt;
}
