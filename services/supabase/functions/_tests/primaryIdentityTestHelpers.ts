import type { SavedIdentificationFields } from "../_shared/identify/effectiveIdentity.ts";
export const fixtureSpeciesID = "00000000-0000-0000-0000-00000000ef01";
export const primaryProvenanceFixture = {
  version: 2,
  provider: "openai",
  binding: "openai_photo_v1",
  model: "gpt-6-sol",
  variant: "multimodal",
  operation: "scan_identification",
  policy_version: 2,
  prompt: "synthetic_primary_fixture_v1",
  schema: "merian_identify_primary_v1",
  confidence: "openai_unqualified_v1",
  diagnostic_trigger: null,
  prompt_diagnostic_trigger: null,
  safety: "openai_photo_moderation_v1",
  timeout_ms: 90000,
  generation: {
    max_output_tokens: 8192,
    reasoning_effort: "low",
    image_detail: "high",
  },
};
export function savedIdentityFixture(
  rank = "genus",
): SavedIdentificationFields {
  return {
    primary_identification: {
      version: 1,
      resolution: rank,
      scientific_name: rank === "unresolved_biological" ? null : "Fixtureus",
      common_name: null,
    },
    identification_provenance: primaryProvenanceFixture,
    is_biological_subject: rank !== "non_biological",
    species_id: null,
    confirmed_species_id: null,
    confirmed_species_identity: null,
    confirmed_species_identity_revision: 0,
    user_identification_override: null,
    user_confirmed_identification: false,
    user_review_state: "unreviewed",
    candidates: null,
    pet_identification: null,
  };
}
