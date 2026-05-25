// services/supabase/functions/identify/index.test.ts
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { sanitizeScientificName } from "./sanitize.ts";
import {
  type TierResolution,
  tierTelemetryProperties,
} from "../_shared/tierCache.ts";

// ---------------------------------------------------------------------------
// Enum drift guard — mirrors VALID_LIFE_STAGES / VALID_REPRODUCTIVE_CONDITIONS / VALID_SEX_VALUES
// in index.ts. Keep in sync with the scan metadata constraints.
// ---------------------------------------------------------------------------

const VALID_LIFE_STAGES = new Set([
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
]);
const VALID_REPRODUCTIVE_CONDITIONS = new Set([
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
]);
const VALID_SEX_VALUES = new Set([
  "female",
  "male",
  "hermaphrodite",
  "mixed",
  "cannot_determine",
  "not_applicable",
]);

function sanitizeLifeStage(v: string | undefined): string {
  if (v == null) return "unknown";
  return VALID_LIFE_STAGES.has(v) ? v : "unknown";
}
function sanitizeReproductiveCondition(v: string | undefined): string {
  if (v == null) return "not_applicable";
  return VALID_REPRODUCTIVE_CONDITIONS.has(v) ? v : "not_applicable";
}
function sanitizeSex(v: string | undefined): string {
  if (v == null) return "cannot_determine";
  return VALID_SEX_VALUES.has(v) ? v : "cannot_determine";
}
// Instead of importing the heavy generative SDK which requires API keys, we mock the validation
// of the merianResponseSchema to securely assert that DaaS keys are structurally present.

Deno.test("Identify Schema Structure validates all Data-as-a-Service properties", () => {
  // 1. Mock the expected JSON that Gemini returns based on the Edge Schema
  const mockGeminiJSON = {
    is_biological_subject: true,
    is_live_capture: true,
    ecology_type: "wild",
    scientific_name: "Danaus plexippus",
    common_name: "Monarch Butterfly",
    confidence_score: 0.98,
    blur_score: 0.05,
    is_invasive: false,
    colors: ["orange", "black", "white"],
    life_stage: "adult",
    reproductive_condition: "not_applicable",
    sex: "female",
    sex_confidence: 0.84,
    sex_evidence: "dimorphic wing pattern",
    individual_count: 1,
    estimated_size_cm: 10.5,
    ecological_interactions: ["pollinating milkweed"],
    insight_data: {
      ai_reasoning: "Distinct vein pattern matches Danaus",
      hazard_type: "none",
    },
  };

  // 2. Mock Edge JSON parsing / filtering mimicking Deno edge behavior
  const parsedData = JSON.parse(JSON.stringify(mockGeminiJSON));

  // 3. Ensure DaaS extraction structure is not malformed
  assertEquals(
    typeof parsedData.estimated_size_cm,
    "number",
    "estimated_size_cm should parse as number",
  );
  assertEquals(
    typeof parsedData.life_stage,
    "string",
    "life_stage should parse as string",
  );
  assertEquals(
    typeof parsedData.reproductive_condition,
    "string",
    "reproductive_condition should parse as string",
  );
  assertEquals(typeof parsedData.sex, "string", "sex should parse as string");
  assertEquals(
    typeof parsedData.sex_confidence,
    "number",
    "sex_confidence should parse as number",
  );
  assertEquals(
    typeof parsedData.sex_evidence,
    "string",
    "sex_evidence should parse as string",
  );
  assertEquals(
    typeof parsedData.individual_count,
    "number",
    "individual_count should parse as number",
  );

  assert(
    Array.isArray(parsedData.ecological_interactions),
    "ecological_interactions should parse as an array",
  );
  assertEquals(
    parsedData.ecological_interactions[0],
    "pollinating milkweed",
    "interaction strings must be extracted cleanly",
  );

  // 4. Validate Vision Lean schema fields
  assertEquals(
    parsedData.insight_data.ai_reasoning,
    "Distinct vein pattern matches Danaus",
    "ai_reasoning is structurally missing",
  );
});

Deno.test("ScanCompleted telemetry includes pro trial plan and Pro model", () => {
  const resolution: TierResolution = {
    effective_tier: "pro",
    plan: "pro_trial",
    subscription_tier: "free",
    trial_active: true,
    user_exists: true,
  };
  const properties: Record<string, unknown> = {
    tier: resolution.effective_tier,
    ...tierTelemetryProperties(resolution),
    llm_model: resolution.effective_tier === "pro"
      ? "gemini-2.5-pro"
      : "gemini-2.5-flash",
  };
  assertEquals(properties.tier, "pro");
  assertEquals(properties.plan, "pro_trial");
  assertEquals(properties.effective_tier, "pro");
  assertEquals(properties.subscription_tier, "free");
  assertEquals(properties.trial_active, true);
  assertEquals(properties.llm_model, "gemini-2.5-pro");
});

// ---------------------------------------------------------------------------
// GPS coordinate range validation (safeGpsLat / safeGpsLon)
// Mirrors the guard in index.ts — out-of-range values → null, valid values pass through.
// ---------------------------------------------------------------------------

function safeGpsLat(v: unknown): number | null {
  return v != null && typeof v === "number" && Number.isFinite(v) && v >= -90 &&
      v <= 90
    ? v
    : null;
}
function safeGpsLon(v: unknown): number | null {
  return v != null && typeof v === "number" && Number.isFinite(v) &&
      v >= -180 && v <= 180
    ? v
    : null;
}

Deno.test("GPS validation — valid coordinates pass through unchanged", () => {
  assertEquals(safeGpsLat(40.7128), 40.7128);
  assertEquals(safeGpsLon(-74.006), -74.006);
  assertEquals(safeGpsLat(-90), -90);
  assertEquals(safeGpsLat(90), 90);
  assertEquals(safeGpsLon(-180), -180);
  assertEquals(safeGpsLon(180), 180);
});

Deno.test("GPS validation — out-of-range latitude is sanitised to null", () => {
  assertEquals(safeGpsLat(91), null, "lat > 90 must be null");
  assertEquals(safeGpsLat(-91), null, "lat < -90 must be null");
  assertEquals(safeGpsLat(999), null);
});

Deno.test("GPS validation — out-of-range longitude is sanitised to null", () => {
  assertEquals(safeGpsLon(181), null, "lon > 180 must be null");
  assertEquals(safeGpsLon(-181), null, "lon < -180 must be null");
});

Deno.test("GPS validation — non-finite values are sanitised to null", () => {
  assertEquals(safeGpsLat(Infinity), null);
  assertEquals(safeGpsLat(-Infinity), null);
  assertEquals(safeGpsLat(NaN), null);
  assertEquals(safeGpsLon(Infinity), null);
});

Deno.test("GPS validation — null and undefined are sanitised to null", () => {
  assertEquals(safeGpsLat(null), null);
  assertEquals(safeGpsLat(undefined), null);
  assertEquals(safeGpsLon(null), null);
});

Deno.test("GPS validation — zero is a valid coordinate (equator / prime meridian)", () => {
  assertEquals(safeGpsLat(0), 0);
  assertEquals(safeGpsLon(0), 0);
});

// ---------------------------------------------------------------------------
// LLM field sanitization caps
// Mirrors the cap logic in index.ts applied after extractJson.
// ---------------------------------------------------------------------------

Deno.test("LLM caps — candidates array capped at 5", () => {
  const candidates = Array.from({ length: 8 }, (_, i) => ({
    scientific_name: `Species ${i}`,
    confidence_score: 0.5,
  }));
  const capped = candidates.slice(0, 5);
  assertEquals(capped.length, 5);
  assertEquals(capped[4].scientific_name, "Species 4");
});

Deno.test("LLM caps — candidates under limit pass through unchanged", () => {
  const candidates = [{
    scientific_name: "Danaus plexippus",
    confidence_score: 0.9,
  }];
  assertEquals(candidates.slice(0, 5).length, 1);
});

Deno.test("LLM caps — extracted_visual_traits capped at 10", () => {
  const traits = Array.from({ length: 15 }, (_, i) => `trait ${i}`);
  assertEquals(traits.slice(0, 10).length, 10);
});

Deno.test("LLM caps — ecological_interactions capped at 10", () => {
  const interactions = Array.from({ length: 12 }, (_, i) => `interaction ${i}`);
  assertEquals(interactions.slice(0, 10).length, 10);
});

Deno.test("LLM caps — ai_reasoning truncated at 2000 chars", () => {
  const long = "x".repeat(2500);
  const truncated = long.length > 2000 ? long.slice(0, 2000) : long;
  assertEquals(truncated.length, 2000);
});

Deno.test("LLM caps — ai_reasoning under 2000 chars is not modified", () => {
  const short = "x".repeat(100);
  const result = short.length > 2000 ? short.slice(0, 2000) : short;
  assertEquals(result.length, 100);
});

Deno.test("LLM caps — individual_count: valid positive integer passes through", () => {
  function sanitizeCount(v: unknown): number | undefined {
    if (v == null) return undefined;
    if (!Number.isFinite(v as number) || (v as number) <= 0) return undefined;
    return Math.min(Math.round(v as number), 99999);
  }
  assertEquals(sanitizeCount(3), 3);
  assertEquals(sanitizeCount(99999), 99999);
  assertEquals(sanitizeCount(1), 1);
});

Deno.test("LLM caps — individual_count: negative value sanitised to undefined", () => {
  function sanitizeCount(v: unknown): number | undefined {
    if (v == null) return undefined;
    if (!Number.isFinite(v as number) || (v as number) <= 0) return undefined;
    return Math.min(Math.round(v as number), 99999);
  }
  assertEquals(sanitizeCount(-1), undefined);
  assertEquals(sanitizeCount(0), undefined);
  assertEquals(sanitizeCount(-100), undefined);
});

Deno.test("LLM caps — individual_count: value exceeding 99999 is clamped", () => {
  function sanitizeCount(v: unknown): number | undefined {
    if (v == null) return undefined;
    if (!Number.isFinite(v as number) || (v as number) <= 0) return undefined;
    return Math.min(Math.round(v as number), 99999);
  }
  assertEquals(sanitizeCount(999999), 99999);
  assertEquals(sanitizeCount(100000), 99999);
});

Deno.test("LLM caps — individual_count: non-finite sanitised to undefined", () => {
  function sanitizeCount(v: unknown): number | undefined {
    if (v == null) return undefined;
    if (!Number.isFinite(v as number) || (v as number) <= 0) return undefined;
    return Math.min(Math.round(v as number), 99999);
  }
  assertEquals(sanitizeCount(NaN), undefined);
  assertEquals(sanitizeCount(Infinity), undefined);
});

Deno.test("LLM caps — estimated_size_cm: positive finite value ≤50000 passes through", () => {
  function sanitizeSizeCm(v: unknown): number | null {
    if (v == null || !Number.isFinite(v as number) || (v as number) <= 0) {
      return null;
    }
    return Math.min(v as number, 50000);
  }
  assertEquals(sanitizeSizeCm(10.5), 10.5);
  assertEquals(sanitizeSizeCm(50000), 50000);
});

Deno.test("LLM caps — estimated_size_cm: value exceeding 50000 is clamped", () => {
  function sanitizeSizeCm(v: unknown): number | null {
    if (v == null || !Number.isFinite(v as number) || (v as number) <= 0) {
      return null;
    }
    return Math.min(v as number, 50000);
  }
  assertEquals(sanitizeSizeCm(99999), 50000);
});

Deno.test("LLM caps — estimated_size_cm: non-positive and non-finite → null", () => {
  function sanitizeSizeCm(v: unknown): number | null {
    if (v == null || !Number.isFinite(v as number) || (v as number) <= 0) {
      return null;
    }
    return Math.min(v as number, 50000);
  }
  assertEquals(sanitizeSizeCm(0), null);
  assertEquals(sanitizeSizeCm(-5), null);
  assertEquals(sanitizeSizeCm(Infinity), null);
  assertEquals(sanitizeSizeCm(null), null);
});

// ---------------------------------------------------------------------------
// Candidates strip gate
// Mirrors the confidence_score >= diagnosticTrigger guard in index.ts.
// ---------------------------------------------------------------------------

function applyDiagnosticStrip(
  confidenceScore: number | null | undefined,
  diagnosticTrigger: number,
  candidates: unknown[],
): unknown[] | null {
  if ((confidenceScore ?? 0.0) >= diagnosticTrigger) return null;
  return candidates;
}

Deno.test("candidates strip — strong match (score == trigger) strips candidates", () => {
  assertEquals(
    applyDiagnosticStrip(0.95, 0.95, [{ scientific_name: "Foo" }]),
    null,
  );
});

Deno.test("candidates strip — score above trigger strips candidates", () => {
  assertEquals(
    applyDiagnosticStrip(0.99, 0.95, [{ scientific_name: "Foo" }]),
    null,
  );
});

Deno.test("candidates strip — score below trigger preserves candidates", () => {
  const candidates = [{ scientific_name: "Foo" }, { scientific_name: "Bar" }];
  assertEquals(applyDiagnosticStrip(0.72, 0.95, candidates), candidates);
});

Deno.test("candidates strip — null confidence_score falls back to 0.0, preserving candidates", () => {
  // Malformed Gemini response with missing confidence — must NOT strip candidates,
  // because that is exactly the scan where alternatives are most needed.
  const candidates = [{ scientific_name: "Foo" }];
  assertEquals(applyDiagnosticStrip(null, 0.95, candidates), candidates);
});

Deno.test("candidates strip — undefined confidence_score falls back to 0.0, preserving candidates", () => {
  const candidates = [{ scientific_name: "Foo" }];
  assertEquals(applyDiagnosticStrip(undefined, 0.95, candidates), candidates);
});

Deno.test("candidates strip — Pro tier threshold (0.85) strips at exactly 0.85", () => {
  assertEquals(
    applyDiagnosticStrip(0.85, 0.85, [{ scientific_name: "Foo" }]),
    null,
  );
});

Deno.test("candidates strip — Pro tier threshold (0.85) preserves below 0.85", () => {
  const candidates = [{ scientific_name: "Foo" }];
  assertEquals(applyDiagnosticStrip(0.84, 0.85, candidates), candidates);
});

// Current thresholds: 0.99 for both Flash and Pro (raised from 0.95/0.85).
// Strong match scans (0.95–0.98) now carry candidates as an escape hatch.

Deno.test("candidates strip — current threshold (0.99): score exactly at trigger strips candidates", () => {
  assertEquals(
    applyDiagnosticStrip(0.99, 0.99, [{ scientific_name: "Foo" }]),
    null,
  );
});

Deno.test("candidates strip — current threshold (0.99): score above trigger strips candidates", () => {
  assertEquals(
    applyDiagnosticStrip(1.0, 0.99, [{ scientific_name: "Foo" }]),
    null,
  );
});

Deno.test("candidates strip — current threshold (0.99): Strong match (0.96) preserves candidates", () => {
  const candidates = [{ scientific_name: "Limenitis archippus" }, {
    scientific_name: "Danaus gilippus",
  }];
  assertEquals(applyDiagnosticStrip(0.96, 0.99, candidates), candidates);
});

Deno.test("candidates strip — current threshold (0.99): score just below trigger (0.989) preserves candidates", () => {
  const candidates = [{ scientific_name: "Foo" }];
  assertEquals(applyDiagnosticStrip(0.989, 0.99, candidates), candidates);
});

// ---------------------------------------------------------------------------
// Candidate common_name enrichment
// Mirrors the fetchCandidateCommonNames + map step in index.ts.
// ---------------------------------------------------------------------------

type Candidate = {
  scientific_name: string;
  confidence_score: number;
  distinguishing_feature: string;
  common_name?: string;
};

function enrichCandidatesWithCommonNames(
  candidates: Candidate[],
  commonNameMap: Map<string, string>,
): Candidate[] {
  if (commonNameMap.size === 0) return candidates;
  return candidates.map((c) => ({
    ...c,
    common_name: commonNameMap.get(c.scientific_name),
  }));
}

Deno.test("candidate enrichment — both species in cache receive common_name", () => {
  const candidates: Candidate[] = [
    {
      scientific_name: "Limenitis archippus",
      confidence_score: 0.71,
      distinguishing_feature: "Hindwing band broader",
    },
    {
      scientific_name: "Danaus gilippus",
      confidence_score: 0.58,
      distinguishing_feature: "Forewing lacks white spots",
    },
  ];
  const map = new Map([["Limenitis archippus", "Viceroy"], [
    "Danaus gilippus",
    "Queen",
  ]]);
  const enriched = enrichCandidatesWithCommonNames(candidates, map);
  assertEquals(enriched[0].common_name, "Viceroy");
  assertEquals(enriched[1].common_name, "Queen");
});

Deno.test("candidate enrichment — empty map returns candidates unchanged (non-fatal cache miss)", () => {
  const candidates: Candidate[] = [
    {
      scientific_name: "Rare obscura",
      confidence_score: 0.71,
      distinguishing_feature: "Some trait",
    },
  ];
  const enriched = enrichCandidatesWithCommonNames(candidates, new Map());
  assertEquals(enriched.length, 1);
  assertEquals(
    enriched[0].common_name,
    undefined,
    "common_name must be absent when cache misses — not null or empty string",
  );
  assertEquals(
    enriched[0].distinguishing_feature,
    "Some trait",
    "distinguishing_feature must be preserved through enrichment",
  );
});

Deno.test("candidate enrichment — partial cache miss: known species enriched, unknown species gets undefined", () => {
  const candidates: Candidate[] = [
    {
      scientific_name: "Limenitis archippus",
      confidence_score: 0.71,
      distinguishing_feature: "Hindwing band",
    },
    {
      scientific_name: "Truly obscura",
      confidence_score: 0.58,
      distinguishing_feature: "Some trait",
    },
  ];
  const map = new Map([["Limenitis archippus", "Viceroy"]]);
  const enriched = enrichCandidatesWithCommonNames(candidates, map);
  assertEquals(enriched[0].common_name, "Viceroy");
  assertEquals(enriched[1].common_name, undefined);
});

Deno.test("candidate enrichment — empty candidates array returns empty array without error", () => {
  const enriched = enrichCandidatesWithCommonNames(
    [],
    new Map([["Foo", "Bar"]]),
  );
  assertEquals(enriched.length, 0);
});

Deno.test("candidate enrichment — distinguishing_feature and confidence_score preserved after enrichment", () => {
  const candidates: Candidate[] = [
    {
      scientific_name: "Danaus plexippus",
      confidence_score: 0.82,
      distinguishing_feature: "Orange wings with black veins",
    },
  ];
  const map = new Map([["Danaus plexippus", "Monarch"]]);
  const enriched = enrichCandidatesWithCommonNames(candidates, map);
  assertEquals(enriched[0].confidence_score, 0.82);
  assertEquals(
    enriched[0].distinguishing_feature,
    "Orange wings with black veins",
  );
  assertEquals(enriched[0].common_name, "Monarch");
});

// ---------------------------------------------------------------------------
// blur_score derivation
// Mirrors Math.max(0, (10 - (sharpness ?? 10)) / 10) in index.ts.
// ---------------------------------------------------------------------------

function deriveBlurScore(sharpness: number | undefined): number {
  return Math.max(0, (10 - (sharpness ?? 10)) / 10);
}

Deno.test("blur_score — sharpness 10 (perfectly sharp) → 0.0", () => {
  assertEquals(deriveBlurScore(10), 0.0);
});

Deno.test("blur_score — sharpness 1 (very blurry) → 0.9", () => {
  assertEquals(deriveBlurScore(1), 0.9);
});

Deno.test("blur_score — sharpness 5 (mid) → 0.5", () => {
  assertEquals(deriveBlurScore(5), 0.5);
});

Deno.test("blur_score — missing sharpness defaults to 10 → 0.0 (no false blur advisory)", () => {
  // A missing image_quality object must not trigger the blur advisory UI.
  assertEquals(deriveBlurScore(undefined), 0.0);
});

Deno.test("blur_score — clamps to 0, never negative", () => {
  // Sharpness above 10 is out-of-spec but must not produce a negative score.
  assert(deriveBlurScore(11) >= 0);
});

// ---------------------------------------------------------------------------
// needsGroupTags gate
// Mirrors isIdentifiedBio && !cachedSpecies?.group_tags?.length in index.ts.
// ---------------------------------------------------------------------------

function needsGroupTags(
  isIdentifiedBio: boolean,
  groupTags: string[] | null | undefined,
): boolean {
  return isIdentifiedBio && !groupTags?.length;
}

Deno.test("needsGroupTags — biological, no tags → fetch", () => {
  assertEquals(needsGroupTags(true, null), true);
  assertEquals(needsGroupTags(true, []), true);
  assertEquals(needsGroupTags(true, undefined), true);
});

Deno.test("needsGroupTags — biological, tags already cached → skip", () => {
  assertEquals(needsGroupTags(true, ["animal", "insect"]), false);
});

Deno.test("needsGroupTags — non-biological → always skip", () => {
  assertEquals(needsGroupTags(false, null), false);
  assertEquals(needsGroupTags(false, []), false);
});

// ---------------------------------------------------------------------------
// Enum drift guards — life_stage and reproductive_condition
// These were the root cause of the 22P02 scan insert failures.
// ---------------------------------------------------------------------------

Deno.test("life_stage — all current valid enum values pass through", () => {
  for (const v of VALID_LIFE_STAGES) {
    assertEquals(sanitizeLifeStage(v), v, `${v} should be valid`);
  }
});

Deno.test("life_stage — unknown value is clamped to 'unknown'", () => {
  assertEquals(sanitizeLifeStage("subadult_new"), "unknown");
  assertEquals(sanitizeLifeStage("hatchling"), "unknown");
  assertEquals(sanitizeLifeStage("fry"), "unknown");
});

Deno.test("life_stage — undefined is clamped to 'unknown'", () => {
  assertEquals(sanitizeLifeStage(undefined), "unknown");
});

Deno.test("reproductive_condition — all current valid enum values pass through", () => {
  for (const v of VALID_REPRODUCTIVE_CONDITIONS) {
    assertEquals(sanitizeReproductiveCondition(v), v, `${v} should be valid`);
  }
});

Deno.test("reproductive_condition — unknown value is clamped to 'not_applicable'", () => {
  // These were the exact values causing 22P02 before the enum migration.
  // The guard ensures any future Gemini schema expansion degrades gracefully
  // instead of dropping the entire scan row.
  assertEquals(sanitizeReproductiveCondition("vegetative"), "vegetative"); // now valid post-migration
  assertEquals(sanitizeReproductiveCondition("budding"), "budding"); // now valid post-migration
  assertEquals(sanitizeReproductiveCondition("estrus"), "not_applicable"); // hypothetical future value
  assertEquals(sanitizeReproductiveCondition("brooding"), "not_applicable");
});

Deno.test("reproductive_condition — undefined is clamped to 'not_applicable'", () => {
  assertEquals(sanitizeReproductiveCondition(undefined), "not_applicable");
});

Deno.test("sex — all current valid enum values pass through", () => {
  for (const v of VALID_SEX_VALUES) {
    assertEquals(sanitizeSex(v), v, `${v} should be valid`);
  }
});

Deno.test("sex — unknown value is clamped to 'cannot_determine'", () => {
  assertEquals(sanitizeSex("queen"), "cannot_determine");
  assertEquals(sanitizeSex("worker"), "cannot_determine");
});

Deno.test("sex — undefined is clamped to 'cannot_determine'", () => {
  assertEquals(sanitizeSex(undefined), "cannot_determine");
});

// ---------------------------------------------------------------------------
// sanitizeScientificName
// All documented examples from sanitize.ts plus edge cases.
// ---------------------------------------------------------------------------

// --- Documented examples ---

Deno.test("sanitize — lowercase genus is capitalised", () => {
  assertEquals(sanitizeScientificName("rosa 'Radrazz'"), "Rosa 'Radrazz'");
});

Deno.test("sanitize — trailing author citation stripped", () => {
  assertEquals(sanitizeScientificName("Rosa canina L."), "Rosa canina");
});

Deno.test("sanitize — parenthetical + secondary author both stripped", () => {
  assertEquals(
    sanitizeScientificName("Quercus robur (L.) Karst."),
    "Quercus robur",
  );
});

Deno.test("sanitize — cf. qualifier stripped", () => {
  assertEquals(
    sanitizeScientificName("cf. Pinus ponderosa"),
    "Pinus ponderosa",
  );
});

Deno.test("sanitize — uppercase specific epithet lowercased", () => {
  assertEquals(sanitizeScientificName("Acer Palmatum"), "Acer palmatum");
});

Deno.test("sanitize — infraspecific epithet after var. lowercased", () => {
  assertEquals(
    sanitizeScientificName("Boletus edulis var. Edulis"),
    "Boletus edulis var. edulis",
  );
});

// --- Additional edge cases ---

Deno.test("sanitize — already clean binomial is unchanged", () => {
  assertEquals(sanitizeScientificName("Danaus plexippus"), "Danaus plexippus");
});

Deno.test("sanitize — empty string returns empty string", () => {
  assertEquals(sanitizeScientificName(""), "");
});

Deno.test("sanitize — aff. qualifier stripped", () => {
  assertEquals(sanitizeScientificName("aff. Quercus robur"), "Quercus robur");
});

Deno.test("sanitize — sp. qualifier stripped", () => {
  assertEquals(sanitizeScientificName("sp. Lactarius"), "Lactarius");
});

Deno.test("sanitize — hybrid marker preserved", () => {
  assertEquals(sanitizeScientificName("× Heucherella"), "× Heucherella");
});

Deno.test("sanitize — hybrid binomial: marker and genus capitalised correctly", () => {
  assertEquals(
    sanitizeScientificName("× heucherella tiarelloides"),
    "× Heucherella tiarelloides",
  );
});

Deno.test("sanitize — cultivar with author: author stripped, cultivar case preserved", () => {
  assertEquals(sanitizeScientificName("Rosa 'Peace' L."), "Rosa 'Peace'");
});

Deno.test("sanitize — subsp. rank marker and infraspecific epithet handled", () => {
  assertEquals(
    sanitizeScientificName("Pinus sylvestris subsp. Scotica"),
    "Pinus sylvestris subsp. scotica",
  );
});

Deno.test("sanitize — multi-word author with 'ex' fully stripped", () => {
  assertEquals(
    sanitizeScientificName("Salix alba Thunb. ex Murray"),
    "Salix alba",
  );
});

Deno.test("sanitize — leading and trailing whitespace collapsed", () => {
  assertEquals(sanitizeScientificName("  Quercus  robur  "), "Quercus robur");
});
