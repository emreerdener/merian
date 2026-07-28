import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type IdentifySuccessEnvelope,
  parseIdentifySuccessEnvelope,
} from "./contract.ts";

const COMPLETED_SCAN_SELECT = [
  "id",
  "user_id",
  "species_id",
  "device_locale",
  "ai_confidence_score",
  "is_biological_subject",
  "is_live_capture",
  "blur_score",
  "ecology_type",
  "is_invasive",
  "invasive_status_region",
  "invasive_rationale",
  "invasive_confidence",
  "colors",
  "estimated_size_cm",
  "life_stage",
  "reproductive_condition",
  "sex",
  "sex_confidence",
  "sex_evidence",
  "individual_count",
  "ecological_interactions",
  "ai_reasoning",
  "extracted_visual_traits",
  "inference_tier",
  "candidates",
  "image_quality_score",
  "pet_identification",
].join(",");

const COMPLETED_SPECIES_SELECT = [
  "id",
  "scientific_name",
  "common_names",
  "alternative_common_names",
  "kingdom",
  "phylum",
  "class",
  "order",
  "family",
  "genus",
  "hazard_type",
  "wikipedia_url",
  "wikipedia_overview",
  "reference_image_url",
  "iucn_red_list_status",
  "habitat_description",
  "gbif_taxon_key",
  "group_tags",
].join(",");

export interface CompletedScanResponseRow {
  id: string;
  user_id: string;
  species_id: string | null;
  device_locale: string | null;
  ai_confidence_score: number | null;
  is_biological_subject: boolean;
  is_live_capture: boolean;
  blur_score: number | null;
  ecology_type: string | null;
  is_invasive: boolean | null;
  invasive_status_region: string | null;
  invasive_rationale: string | null;
  invasive_confidence: number | null;
  colors: string[] | null;
  estimated_size_cm: number | null;
  life_stage: string | null;
  reproductive_condition: string | null;
  sex: string | null;
  sex_confidence: number | null;
  sex_evidence: string | null;
  individual_count: number | null;
  ecological_interactions: string[] | null;
  ai_reasoning: string | null;
  extracted_visual_traits: string[] | null;
  inference_tier: string | null;
  candidates: Array<Record<string, unknown>> | null;
  image_quality_score: number | null;
  pet_identification: Record<string, unknown> | null;
}

export interface CompletedSpeciesResponseRow {
  id: string;
  scientific_name: string;
  common_names: Record<string, string | null> | null;
  alternative_common_names: string[] | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  hazard_type: string | null;
  wikipedia_url: string | null;
  wikipedia_overview: string | null;
  reference_image_url: string | null;
  iucn_red_list_status: string | null;
  habitat_description: string | null;
  gbif_taxon_key: number | null;
  group_tags: string[] | null;
}

export interface CompletedIdentifyResponse {
  envelope: IdentifySuccessEnvelope;
  source: "stored" | "reconstructed";
}

type DatabaseRoutineError = {
  code?: string | null;
  message?: string | null;
};

const COMPLETED_RESPONSE_POLL_DELAYS_MS = [
  0,
  100,
  250,
  500,
  1_000,
  2_000,
  3_000,
  4_000,
  5_000,
] as const;
export const COMPLETED_RESPONSE_POLL_TIMEOUT_MS = 70_000;
const COMPLETED_RESPONSE_STEADY_POLL_MS = 5_000;
const COMPLETED_RESPONSE_DATABASE_TIMEOUT_MS = 5_000;

function clamp(value: unknown, minimum: number, maximum: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return minimum;
  return Math.min(maximum, Math.max(minimum, value));
}

function firstNonEmpty(
  values: unknown[],
): string | null {
  for (const value of values) {
    if (typeof value !== "string") continue;
    const trimmed = value.trim();
    if (trimmed) return trimmed;
  }
  return null;
}

function boundedText(value: unknown, maximumLength: number): string | null {
  return firstNonEmpty([value])?.slice(0, maximumLength) ?? null;
}

function boundedTextList(
  value: unknown,
  maximumItems: number,
  maximumLength: number,
): string[] {
  if (!Array.isArray(value)) return [];
  const values: string[] = [];
  const observed = new Set<string>();
  for (const item of value) {
    const bounded = boundedText(item, maximumLength);
    if (!bounded || observed.has(bounded)) continue;
    observed.add(bounded);
    values.push(bounded);
    if (values.length === maximumItems) break;
  }
  return values;
}

function allowedText<const Value extends string>(
  value: unknown,
  allowed: readonly Value[],
): Value | null {
  return typeof value === "string" &&
      allowed.includes(value as Value)
    ? value as Value
    : null;
}

function nullableConfidence(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value)
    ? clamp(value, 0, 1)
    : null;
}

function nullableInteger(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.round(clamp(value, minimum, maximum))
    : null;
}

function isMissingDatabaseRoutine(
  error: DatabaseRoutineError,
  routineName: string,
): boolean {
  if (error.code === "PGRST202") return true;
  return error.code === "42883" &&
    (error.message ?? "").includes(routineName);
}

async function recoverStrandedInlineCompletion(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc(
    "recover_inline_scan_ingestion_completion",
    {
      p_scan_id: scanId,
      p_user_id: userId,
    },
  );
  if (error) {
    // The repair routine is additive. Old isolates must continue through the
    // established retry path while a migration-first rollout reaches every
    // database/schema-cache instance.
    if (
      isMissingDatabaseRoutine(
        error,
        "recover_inline_scan_ingestion_completion",
      )
    ) {
      return false;
    }
    throw new Error(
      `recoverStrandedInlineCompletion: ${error.message ?? error.code}`,
    );
  }
  return data === "completed" || data === "already_complete";
}

function sanitizedCandidates(
  value: unknown,
): Array<Record<string, unknown>> | null {
  if (!Array.isArray(value)) return null;
  const candidates: Array<Record<string, unknown>> = [];
  for (const item of value) {
    if (item == null || typeof item !== "object" || Array.isArray(item)) {
      continue;
    }
    const candidate = item as Record<string, unknown>;
    const scientificName = boundedText(candidate.scientific_name, 255);
    if (!scientificName) continue;
    const sanitized: Record<string, unknown> = {
      scientific_name: scientificName,
      confidence_score: clamp(candidate.confidence_score, 0, 1),
      distinguishing_feature: boundedText(
        candidate.distinguishing_feature,
        500,
      ) ?? "Saved alternative identification.",
    };
    const commonName = boundedText(candidate.common_name, 255);
    if (commonName) sanitized.common_name = commonName;
    candidates.push(sanitized);
    if (candidates.length === 5) break;
  }
  return candidates;
}

function sanitizedPetIdentification(
  value: unknown,
): Record<string, unknown> | null {
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const pet = value as Record<string, unknown>;
  const speciesGroup = allowedText(pet.species_group, ["dog", "cat"]);
  const label = boundedText(pet.label, 160);
  const labelType = allowedText(pet.label_type, [
    "breed",
    "breed_mix",
    "coat_pattern",
    "body_type",
  ]);
  const evidence = boundedTextList(pet.evidence, 3, 500);
  if (!speciesGroup || !label || !labelType || evidence.length === 0) {
    return null;
  }
  return {
    species_group: speciesGroup,
    label,
    label_type: labelType,
    confidence_score: clamp(pet.confidence_score, 0, 1),
    evidence,
  };
}

function commonNameForLocale(
  names: Record<string, string | null> | null,
  deviceLocale: string | null,
  scientificName: string | null,
): string | null {
  if (!names || typeof names !== "object" || Array.isArray(names)) {
    return scientificName;
  }
  const locale = deviceLocale?.trim().replace("_", "-").toLowerCase() ?? "";
  const language = locale.split("-")[0];
  return boundedText(
    firstNonEmpty([
      locale ? names[locale] : null,
      language ? names[language] : null,
      names.en,
      ...Object.values(names),
      scientificName,
    ]),
    255,
  );
}

function optionalRecord(
  entries: Array<[string, unknown]>,
): Record<string, unknown> | undefined {
  const record = Object.fromEntries(
    entries.filter(([, value]) => value != null && value !== ""),
  );
  return Object.keys(record).length > 0 ? record : undefined;
}

/**
 * Reconstructs the Identify wire envelope for completed rows created before
 * canonical response persistence existed. Every required wire field receives
 * a deterministic value; fields that cannot be recovered exactly are omitted
 * or conservatively derived from their persisted summary.
 */
export function buildCompletedIdentifyEnvelope(
  scan: CompletedScanResponseRow,
  species: CompletedSpeciesResponseRow | null,
): IdentifySuccessEnvelope {
  const confidence = clamp(scan.ai_confidence_score, 0, 1);
  const blurScore = clamp(scan.blur_score, 0, 1);
  const imageQualityScore = Math.round(
    clamp(scan.image_quality_score, 0, 100),
  );
  const tenPointQuality = Math.round(imageQualityScore / 10);
  const scientificName = boundedText(species?.scientific_name, 255);
  const commonName = commonNameForLocale(
    species?.common_names ?? null,
    scan.device_locale,
    scientificName,
  );
  const aiReasoning = boundedText(scan.ai_reasoning, 2_000) ??
    "This completed observation was restored from its saved result.";
  const extractedVisualTraits = boundedTextList(
    scan.extracted_visual_traits,
    10,
    500,
  );
  const taxonomy = optionalRecord([
    ["kingdom", boundedText(species?.kingdom, 160)],
    ["phylum", boundedText(species?.phylum, 160)],
    ["class", boundedText(species?.class, 160)],
    ["order", boundedText(species?.order, 160)],
    ["family", boundedText(species?.family, 160)],
    ["genus", boundedText(species?.genus, 160)],
  ]);
  const insightData = optionalRecord([
    ["ai_reasoning", aiReasoning],
    [
      "hazard_type",
      allowedText(species?.hazard_type, [
        "none",
        "poisonous",
        "venomous",
        "allergenic",
        "irritant",
      ]) ?? "none",
    ],
  ]);
  const speciesInsights = optionalRecord([
    [
      "habitat_description",
      boundedText(species?.habitat_description, 10_000),
    ],
  ]);
  const inferenceTier = scan.inference_tier === "pro" ? "pro" : "flash";
  const candidates = sanitizedCandidates(scan.candidates);

  const data: Record<string, unknown> = {
    scan_id: scan.id,
    is_biological_subject: scan.is_biological_subject === true,
    is_live_capture: scan.is_live_capture === true,
    confidence_score: confidence,
    blur_score: blurScore,
    colors: boundedTextList(scan.colors, 20, 160),
    estimated_size_cm: scan.estimated_size_cm == null
      ? null
      : clamp(scan.estimated_size_cm, 0, 50_000),
    inference_tier: inferenceTier,
    pet_identification: sanitizedPetIdentification(scan.pet_identification),
    candidates,
    image_quality: {
      sharpness: tenPointQuality,
      framing: tenPointQuality,
      diagnostic_utility: tenPointQuality,
      overall_score: imageQualityScore,
    },
    is_new_to_merian_dictionary: false,
    ai_reasoning: aiReasoning,
    extracted_visual_traits: extractedVisualTraits.length > 0
      ? extractedVisualTraits
      : ["saved observation result"],
  };

  const optionalFields: Array<[string, unknown]> = [
    [
      "ecology_type",
      allowedText(scan.ecology_type, [
        "wild",
        "urban",
        "domesticated",
        "unknown",
      ]),
    ],
    [
      "is_invasive",
      typeof scan.is_invasive === "boolean" ? scan.is_invasive : null,
    ],
    [
      "invasive_status_region",
      boundedText(scan.invasive_status_region, 160),
    ],
    ["invasive_rationale", boundedText(scan.invasive_rationale, 500)],
    ["invasive_confidence", nullableConfidence(scan.invasive_confidence)],
    ["scientific_name", scientificName],
    ["common_name", commonName],
    ["group_tags", boundedTextList(species?.group_tags, 32, 160)],
    [
      "life_stage",
      allowedText(scan.life_stage, [
        "egg",
        "larva",
        "pupa",
        "nymph",
        "juvenile",
        "subadult",
        "adult",
        "seedling",
        "sapling",
        "unknown",
      ]),
    ],
    [
      "reproductive_condition",
      allowedText(scan.reproductive_condition, [
        "flowering",
        "fruiting",
        "budding",
        "vegetative",
        "sporing",
        "pregnant",
        "gravid",
        "mating",
        "spawning",
        "nesting",
        "dormant",
        "not_applicable",
      ]),
    ],
    [
      "sex",
      allowedText(scan.sex, [
        "female",
        "male",
        "hermaphrodite",
        "mixed",
        "cannot_determine",
        "not_applicable",
      ]),
    ],
    ["sex_confidence", nullableConfidence(scan.sex_confidence)],
    ["sex_evidence", boundedText(scan.sex_evidence, 500)],
    [
      "individual_count",
      nullableInteger(scan.individual_count, 1, 99_999),
    ],
    [
      "ecological_interactions",
      Array.isArray(scan.ecological_interactions)
        ? boundedTextList(scan.ecological_interactions, 10, 500)
        : null,
    ],
    ["taxonomy", taxonomy],
    ["insight_data", insightData],
    ["species_insights", speciesInsights],
    [
      "gbif_taxon_key",
      nullableInteger(species?.gbif_taxon_key, 0, Number.MAX_SAFE_INTEGER),
    ],
    ["wikipedia_url", boundedText(species?.wikipedia_url, 4_096)],
    [
      "wikipedia_overview",
      boundedText(species?.wikipedia_overview, 20_000),
    ],
    [
      "reference_image_url",
      boundedText(species?.reference_image_url, 4_096),
    ],
    [
      "iucn_red_list_status",
      boundedText(species?.iucn_red_list_status, 160),
    ],
    [
      "alternative_common_names",
      Array.isArray(species?.alternative_common_names)
        ? boundedTextList(species.alternative_common_names, 100, 255)
        : null,
    ],
  ];
  for (const [key, value] of optionalFields) {
    if (value != null && value !== "") data[key] = value;
  }

  return parseIdentifySuccessEnvelope({ success: true, data });
}

/**
 * Loads the immutable completed response, or reconstructs an exact-owner
 * response once the moderated analysis row itself is durable. Scan insertion
 * happens only after every provider result is parsed, wire-validated, safety
 * moderated, and its legacy media URLs are promoted. The later finalizer links
 * normalized media and marks the ledger complete; losing that callback must
 * not hide an otherwise durable analysis or trigger a second provider call.
 */
export async function fetchCompletedIdentifyResponse(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<CompletedIdentifyResponse | null> {
  const { data: jobData, error: jobError } = await supabaseAdmin
    .from("scan_ingestion_jobs")
    // Keep the normal request path compatible with a migration-first rollout:
    // response_envelope is optional replay state and must not make every new
    // scan fail merely because that column is not visible in the schema cache.
    .select("status")
    .eq("scan_id", scanId)
    .eq("user_id", userId)
    .abortSignal(AbortSignal.timeout(COMPLETED_RESPONSE_DATABASE_TIMEOUT_MS))
    .maybeSingle();
  if (jobError) {
    throw new Error(
      `fetchCompletedIdentifyResponse/job: ${jobError.message}`,
    );
  }

  let job = jobData as {
    status?: unknown;
  } | null;
  if (
    job?.status === "failed_retryable" &&
    await recoverStrandedInlineCompletion(
      scanId,
      userId,
      supabaseAdmin,
    )
  ) {
    job = { status: "complete" };
  }
  if (
    job?.status !== "complete" &&
    job?.status !== "processing" &&
    job?.status !== "finalizing" &&
    job?.status !== "retrying" &&
    job?.status !== "failed_retryable"
  ) {
    return null;
  }

  if (job?.status === "complete") {
    const { data: responseData } = await supabaseAdmin
      .from("scan_ingestion_jobs")
      .select("response_envelope")
      .eq("scan_id", scanId)
      .eq("user_id", userId)
      .abortSignal(AbortSignal.timeout(COMPLETED_RESPONSE_DATABASE_TIMEOUT_MS))
      .maybeSingle();
    const storedResponse = (
      responseData as { response_envelope?: unknown } | null
    )?.response_envelope;
    if (storedResponse != null) {
      try {
        const envelope = parseIdentifySuccessEnvelope(storedResponse);
        if (envelope.data.scan_id === scanId) {
          return { envelope, source: "stored" };
        }
      } catch {
        // Fall through to reconstruction. A malformed stored value must never
        // turn an otherwise durable scan into a permanent client failure.
      }
    }
  }

  const { data: scanData, error: scanError } = await supabaseAdmin
    .from("scans")
    .select(COMPLETED_SCAN_SELECT)
    .eq("id", scanId)
    .eq("user_id", userId)
    .abortSignal(AbortSignal.timeout(COMPLETED_RESPONSE_DATABASE_TIMEOUT_MS))
    .maybeSingle();
  if (scanError) {
    throw new Error(
      `fetchCompletedIdentifyResponse/scan: ${scanError.message}`,
    );
  }
  if (!scanData) return null;

  const scan = scanData as unknown as CompletedScanResponseRow;
  let species: CompletedSpeciesResponseRow | null = null;
  if (scan.species_id) {
    const { data: speciesData, error: speciesError } = await supabaseAdmin
      .from("species_dictionary")
      .select(COMPLETED_SPECIES_SELECT)
      .eq("id", scan.species_id)
      .abortSignal(AbortSignal.timeout(COMPLETED_RESPONSE_DATABASE_TIMEOUT_MS))
      .maybeSingle();
    if (speciesError) {
      throw new Error(
        `fetchCompletedIdentifyResponse/species: ${speciesError.message}`,
      );
    }
    species = speciesData as unknown as CompletedSpeciesResponseRow | null;
  }

  return {
    envelope: buildCompletedIdentifyEnvelope(scan, species),
    source: "reconstructed",
  };
}

/**
 * Coalesces a duplicate request with the invocation that still owns provider
 * or durable-finalization work. The 70-second bound fits within the 90-second
 * iOS inference request while covering normal provider and persistence time.
 */
export async function waitForCompletedIdentifyResponse(
  scanId: string,
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<CompletedIdentifyResponse | null> {
  const deadline = Date.now() + COMPLETED_RESPONSE_POLL_TIMEOUT_MS;
  let pollIndex = 0;
  while (Date.now() < deadline) {
    const delayMs = pollIndex < COMPLETED_RESPONSE_POLL_DELAYS_MS.length
      ? COMPLETED_RESPONSE_POLL_DELAYS_MS[pollIndex]
      : COMPLETED_RESPONSE_STEADY_POLL_MS;
    pollIndex += 1;
    if (delayMs > 0) {
      const remainingMs = deadline - Date.now();
      if (remainingMs <= 0) break;
      await new Promise((resolve) =>
        setTimeout(resolve, Math.min(delayMs, remainingMs))
      );
    }
    const replay = await fetchCompletedIdentifyResponse(
      scanId,
      userId,
      supabaseAdmin,
    );
    if (replay) return replay;
  }
  return null;
}
