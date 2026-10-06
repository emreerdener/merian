/** Closed storage contract. SQL projection is the producer; this is not a public DTO. */
export function invalidStoredContext(): never {
  throw new Error("field_chat_context_unavailable");
}
export function storedObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalidStoredContext();
  }
  return value as Record<string, unknown>;
}
export function exactStoredObject(value: unknown, keys: readonly string[]) {
  const row = storedObject(value);
  if (
    Object.keys(row).length !== keys.length ||
    keys.some((key) => !Object.hasOwn(row, key))
  ) return invalidStoredContext();
  return row;
}
export function storedUUID(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      value,
    )
  ) return invalidStoredContext();
  return value;
}
export function storedText(value: unknown, max: number): string {
  if (typeof value !== "string" || Array.from(value).length > max) {
    return invalidStoredContext();
  }
  return value;
}
export function storedRevision(value: unknown, minimum = 0): number {
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < minimum ||
    value > 2147483646
  ) return invalidStoredContext();
  return value;
}
export function parseChatContextTicket(value: unknown) {
  if (value === null) return null;
  const row = exactStoredObject(value, [
    "analysis_id",
    "state_revision",
    "review_revision",
  ]);
  return Object.freeze({
    analysis_id: storedUUID(row.analysis_id),
    state_revision: storedRevision(row.state_revision, 1),
    review_revision: storedRevision(row.review_revision),
  });
}
export type ChatContextTicket = ReturnType<typeof parseChatContextTicket>;
export function sameChatContextTicket(
  a: ChatContextTicket,
  b: ChatContextTicket,
): boolean {
  return a === null || b === null ? a === b : a.analysis_id === b.analysis_id &&
    a.state_revision === b.state_revision &&
    a.review_revision === b.review_revision;
}
export function boundedStoredJSON(value: unknown, max: number) {
  let encoded: string | undefined;
  try {
    encoded = JSON.stringify(value);
  } catch {
    return invalidStoredContext();
  }
  if (
    encoded === undefined || new TextEncoder().encode(encoded).byteLength > max
  ) return invalidStoredContext();
}
type Rule = (value: unknown) => void;
const text: Rule = (v) => {
  storedText(v, 4000);
};
const number: Rule = (v) => {
  if (typeof v !== "number" || !Number.isFinite(v)) invalidStoredContext();
};
const bool: Rule = (v) => {
  if (typeof v !== "boolean") invalidStoredContext();
};
const uuid: Rule = (v) => {
  storedUUID(v);
};
const nullable = (rule: Rule): Rule => (v) => {
  if (v !== null) rule(v);
};
const fields = (names: string, rule: Rule) =>
  Object.fromEntries(names.split(" ").map((key) => [key, nullable(rule)]));
const strings = (maxItems: number, maxChars: number): Rule => (v) => {
  if (!Array.isArray(v) || v.length > maxItems) return invalidStoredContext();
  v.forEach((item) => storedText(item, maxChars));
};
function shape(
  rules: Record<string, Rule>,
  required: readonly string[] = [],
): Rule {
  return (value) => {
    const row = storedObject(value);
    if (required.some((key) => !Object.hasOwn(row, key))) {
      invalidStoredContext();
    }
    for (const [key, entry] of Object.entries(row)) {
      const rule = rules[key];
      if (!Object.hasOwn(rules, key)) invalidStoredContext();
      rule(entry);
    }
  };
}
const primary = shape({
  ...fields("version", number),
  ...fields("resolution scientific_name common_name", text),
}, ["version", "resolution", "scientific_name", "common_name"]);
const identity = shape({
  ...fields("version gbif_taxon_key", number),
  ...fields("scientific_name common_name", text),
  ...fields("species_id", uuid),
}, [
  "version",
  "gbif_taxon_key",
  "scientific_name",
  "common_name",
  "species_id",
]);
const provenance = shape({
  ...fields(
    "version policy_version diagnostic_trigger prompt_diagnostic_trigger timeout_ms",
    number,
  ),
  ...fields(
    "provider binding model variant operation prompt schema confidence safety",
    text,
  ),
  generation: shape({
    ...fields(
      "temperature seed top_k max_output_tokens thinking_budget",
      number,
    ),
    ...fields("reasoning_effort image_detail", text),
  }),
}, ["generation"]);
const review = shape({
  ...fields("version revision", number),
  ...fields("state operation_digest", text),
  ...fields("origin_scan_id operation_id", uuid),
  origin_identification: nullable(
    shape(fields("scientific_name common_name", text), [
      "scientific_name",
      "common_name",
    ]),
  ),
  community: nullable(
    shape({
      ...fields("request_id species_id", uuid),
      ...fields("rank scientific_name common_name", text),
    }, ["request_id", "species_id", "rank", "scientific_name", "common_name"]),
  ),
}, [
  "version",
  "revision",
  "state",
  "origin_scan_id",
  "operation_id",
  "operation_digest",
  "origin_identification",
  "community",
]);
const candidate = shape({
  ...fields(
    "taxon_rank scientific_name common_name distinguishing_feature",
    (v) => {
      storedText(v, 500);
    },
  ),
  ...fields("confidence_score", number),
});
const dictionary = shape({
  ...fields("id", uuid),
  ...fields(
    "scientific_name wikipedia_overview habitat_description hazard_type kingdom phylum class order family genus iucn_red_list_status",
    text,
  ),
  common_names: shape(fields("en", (v) => {
    storedText(v, 255);
  })),
  alternative_common_names: strings(10, 255),
  similar_species: strings(10, 255),
  group_tags: strings(10, 255),
}, [
  "id",
  "scientific_name",
  "common_names",
  "alternative_common_names",
  "similar_species",
  "group_tags",
]);
const requiredScanKeys = [
  "extracted_visual_traits",
  "colors",
  "ecological_interactions",
  "primary_identification",
  "confirmed_species_identity",
  "identification_provenance",
  "ai_identification_review",
  "user_observation_context",
  "pet_identification",
  "candidates",
  "species_dictionary",
  "confirmed_species",
];
const scan = shape({
  // Older immutable snapshots lack this marker and cannot qualify scores.
  metrics_qualified: bool,
  ...fields(
    "timestamp weather_condition semantic_location time_of_day depth_scale_text inference_tier ai_reasoning ecology_type life_stage reproductive_condition sex sex_evidence invasive_status_region invasive_rationale user_identification_override user_review_state",
    text,
  ),
  ...fields(
    "gps_elevation weather_temperature_f current_month ai_confidence_score image_quality_score blur_score zoom_factor estimated_size_cm individual_count sex_confidence invasive_confidence confirmed_species_identity_revision",
    number,
  ),
  ...fields(
    "is_invasive is_biological_subject user_confirmed_identification",
    bool,
  ),
  ...fields("confirmed_species_id species_id", uuid),
  extracted_visual_traits: strings(10, 500),
  colors: strings(10, 500),
  ecological_interactions: strings(10, 500),
  primary_identification: nullable(primary),
  confirmed_species_identity: nullable(identity),
  identification_provenance: nullable(provenance),
  ai_identification_review: nullable(review),
  user_observation_context: nullable(shape(fields("free_text freeText", text))),
  pet_identification: nullable(
    shape({
      ...fields("species_group label label_type", text),
      ...fields("confidence_score", number),
      evidence: strings(3, 500),
    }, ["evidence"]),
  ),
  candidates: nullable((v) => {
    if (!Array.isArray(v) || v.length > 6) return invalidStoredContext();
    v.forEach(candidate);
  }),
  species_dictionary: nullable(dictionary),
  confirmed_species: nullable(dictionary),
}, requiredScanKeys);
export function validateStoredScanContext(
  value: unknown,
): Readonly<Record<string, unknown>> {
  scan(value);
  return storedObject(value);
}
/** Freeze a detached JSON tree; the caller cannot mutate execution context later. */
export function immutableStoredCopy<T>(value: T): T {
  const copied = structuredClone(value);
  function freeze(child: unknown) {
    if (child && typeof child === "object") {
      Object.values(child).forEach(freeze);
      Object.freeze(child);
    }
  }
  freeze(copied);
  return copied;
}
