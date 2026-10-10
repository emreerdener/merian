import { FIELD_CHAT_SPECIES_KNOWLEDGE_RULES } from "../_shared/fieldChat/speciesKnowledge.ts";
import {
  effectiveIdentification,
  type SavedIdentificationFields,
} from "../_shared/identify/effectiveIdentity.ts";
import { isFieldChatEligibleIdentity } from "./eligibility.ts";
import {
  CHAT_RESPONSE_FORMAT,
  CONTEXT_CACHE_ANCHOR,
  formatObservationTraits,
} from "./prompt.ts";
import type { PreparedInsightChatContext } from "./preparedContext.ts";
import type { StoredInsightChatTurnContext } from "./storedContext.ts";
import {
  immutableStoredCopy,
  invalidStoredContext,
  storedObject,
  validateStoredScanContext,
} from "./storedContextContract.ts";

type Context = PreparedInsightChatContext | StoredInsightChatTurnContext;
const text = (v: unknown): string | null => typeof v === "string" ? v : null;
const boolean = (v: unknown): boolean | null =>
  typeof v === "boolean" ? v : null;
/** Explicit optional fields, never a cast to the mutable scan/database model. */
function identityFields(
  scan: Readonly<Record<string, unknown>>,
): SavedIdentificationFields {
  return {
    primary_identification: scan.primary_identification,
    identification_provenance: scan.identification_provenance,
    confirmed_species_identity: scan.confirmed_species_identity,
    confirmed_species_identity_revision:
      scan.confirmed_species_identity_revision,
    ai_identification_review: scan.ai_identification_review,
    candidates: scan.candidates,
    pet_identification: scan.pet_identification,
    species_id: text(scan.species_id),
    confirmed_species_id: text(scan.confirmed_species_id),
    user_identification_override: text(scan.user_identification_override),
    user_review_state: text(scan.user_review_state),
    user_confirmed_identification: boolean(scan.user_confirmed_identification),
    is_biological_subject: boolean(scan.is_biological_subject),
  };
}
function pick(
  source: Readonly<Record<string, unknown>>,
  keys: readonly string[],
) {
  return Object.fromEntries(
    keys.map((key) => [key, source[key] ?? "Unavailable"]),
  );
}
/** Pure, detached prompt data. Operational identity and provider metadata end here. */
export function immutableChatSemantics(context: Context) {
  const scan = validateStoredScanContext(context.scan_context);
  const fields = identityFields(scan);
  const identity = effectiveIdentification(fields);
  if (identity.source === "invalid") return invalidStoredContext();
  const dictionaryValue = identity.source === "legacy"
    ? (fields.confirmed_species_id
      ? scan.confirmed_species
      : scan.species_dictionary)
    : (identity.verified ? scan.confirmed_species : scan.species_dictionary);
  const dictionaryCandidate = dictionaryValue == null
    ? null
    : storedObject(dictionaryValue);
  const dictionary = dictionaryCandidate?.id === identity.species_id
    ? dictionaryCandidate
    : null;
  const eligible = isFieldChatEligibleIdentity(
    fields,
    dictionary?.scientific_name,
  );
  // The original-source marker prevents sanitization from laundering unknown
  // provenance. Older snapshots deliberately remain unqualified.
  const metricsQualified = scan.metrics_qualified === true;
  const candidateKeys = [
    "scientific_name",
    "common_name",
    "distinguishing_feature",
    ...(metricsQualified ? ["confidence_score"] : []),
  ];
  const candidates = Array.isArray(scan.candidates)
    ? scan.candidates.map((candidate) =>
      pick(storedObject(candidate), candidateKeys)
    )
    : null;
  const observation = scan.user_observation_context == null
    ? null
    : storedObject(scan.user_observation_context);
  const pet = scan.pet_identification == null
    ? null
    : storedObject(scan.pet_identification);
  const data = {
    identification: {
      source: identity.source,
      rank: identity.rank,
      scientific_name: identity.scientific_name ??
        text(dictionary?.scientific_name),
      common_name: identity.common_name,
      verified_taxonomy: identity.verified,
      pending_review: identity.pending_review,
      owner_override: fields.user_identification_override,
      owner_confirmed: fields.user_confirmed_identification,
      owner_review_state: fields.user_review_state,
      original_ai: identity.primary
        ? {
          resolution: identity.primary.resolution,
          scientific_name: identity.primary.scientific_name,
          common_name: identity.primary.common_name,
        }
        : null,
    },
    encounter: pick(scan, [
      "timestamp",
      "gps_elevation",
      "weather_condition",
      "weather_temperature_f",
      "semantic_location",
      "current_month",
      "time_of_day",
      "depth_scale_text",
      "ecology_type",
    ]),
    observations: pick(scan, [
      "ai_reasoning",
      "colors",
      "ecological_interactions",
      "life_stage",
      "reproductive_condition",
      "estimated_size_cm",
      "individual_count",
      "sex",
      "sex_evidence",
      "is_invasive",
      "invasive_status_region",
      "invasive_rationale",
    ]),
    observation_traits: formatObservationTraits(scan.extracted_visual_traits),
    user_observation: text(observation?.free_text) ??
      text(observation?.freeText),
    descriptive_candidates: candidates,
    pet: pet
      ? pick(pet, [
        "species_group",
        "label",
        "label_type",
        "evidence",
        ...(metricsQualified ? ["confidence_score"] : []),
      ])
      : null,
    metrics: metricsQualified
      ? pick(scan, [
        "ai_confidence_score",
        "image_quality_score",
        "sex_confidence",
        "invasive_confidence",
      ])
      : "Unavailable (model metrics are not qualified for interpretation)",
    dictionary: dictionary
      ? pick(dictionary, [
        "scientific_name",
        "common_names",
        "alternative_common_names",
        "wikipedia_overview",
        "habitat_description",
        "hazard_type",
        "kingdom",
        "phylum",
        "class",
        "order",
        "family",
        "genus",
        "iucn_red_list_status",
        "similar_species",
        "group_tags",
      ])
      : null,
  };
  return immutableStoredCopy({ eligible, metricsQualified, data });
}
export function buildImmutableChatSystemInstruction(context: Context): string {
  const semantic = immutableChatSemantics(context);
  if (!semantic.eligible) throw new Error("field_chat_subject_ineligible");
  const flag = context.scan_context.is_invasive;
  return `${CONTEXT_CACHE_ANCHOR}\n[SAVED IMMUTABLE CONTEXT]\nNaturebook Invasive Flag: ${
    flag === true ? "Yes" : flag === false ? "No" : "Unavailable"
  }\n${
    JSON.stringify(semantic.data)
  }\n\n${FIELD_CHAT_SPECIES_KNOWLEDGE_RULES}\n\n${CHAT_RESPONSE_FORMAT}`;
}
/** Only an admitted snapshot has a prefix. Preserve exact saved role/text order. */
export function buildImmutableChatUserPrompt(
  context: StoredInsightChatTurnContext,
  question: string,
): string {
  const prefix = context.conversation_prefix;
  return `[CHAT HISTORY]\n${
    prefix.length === 0
      ? "No prior messages."
      : prefix.map((turn) =>
        `${turn.role === "user" ? "User" : "Naturebook"}: ${turn.text}`
      ).join("\n")
  }\n\n[CURRENT USER QUESTION]\n${question}`;
}
