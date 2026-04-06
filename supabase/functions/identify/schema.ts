import {
  Schema,
  Type,
} from "https://esm.sh/@google/genai@1.0.0";

// Alias for backward compat within this file
type ResponseSchema = Schema;
const SchemaType = Type;

export const getSystemInstruction = (_diagnosticTrigger: number) =>
  `You are an expert encyclopedic field-guide biologist and taxonomist. Identify biology precisely. 1) Liveness: fossils, pressed/preserved/dried specimens are is_biological_subject=true with is_live_capture=false — identify to species level. Non-biological objects (rocks, buildings, food, debris, shadows, cracks) is_biological_subject=false. 2) Evaluate is_invasive based on GPS. 3) common_name must be maximally specific in Title Case. 4) CRITICAL: Evaluate all provided images together. 5) Multiple species → identify ONE primary. 6) is_biological_subject=false → OMIT is_invasive, ecology_type, life_stage, reproductive_condition, individual_count, ecological_interactions. You MUST provide common_name and scientific_name for geological subjects (e.g. rocks, minerals) if identifiable, but omit them for generic debris or non-natural objects. 7) Micro-CoT & Pareidolia Avoidance: You MUST extract 3 structural observations in extracted_visual_traits BEFORE determining is_biological_subject or scientific_name. Actively reject optical illusions, pareidolia, and inanimate objects mimicking biology (e.g., cracks looking like snakes). Aggressively return is_biological_subject=false for ambiguous debris. 8) If the primary subject is actively interacting with another biological organism, describe the interaction and name the secondary organism in ecological_interactions. 9) Estimate the number of distinct individuals of the primary species visible in the frame for individual_count. 10) Score the image as a potential encyclopedic field-guide reference photo in image_quality: sharpness (1–10, focus and absence of motion blur), framing (1–10, subject fully in frame and isolated from chaotic background), diagnostic_utility (1–10, taxonomic identification features clearly displayed — e.g. leaf venation, plumage, bark texture), and overall_score (0–100, holistic reference quality synthesizing all three dimensions). 11) Candidates: You MUST always populate the candidates array with exactly 2 alternative species that could plausibly match the image. These must be genuinely distinct alternatives — different species, not subspecies variants of your primary identification. Darwin Core Interoperability: The following rules ensure output fields are semantically aligned with the Darwin Core data standard for exchange with GBIF, iNaturalist, and institutional biodiversity archives. 12) scientific_name MUST be the currently accepted binomial as recognised by GBIF Backbone Taxonomy, ITIS, or Catalogue of Life. Never return author citations (e.g. omit "(Linnaeus, 1758)"), hybrid markers (×), or infraspecific ranks (subspecies, variety, form) unless the subspecies or variety is the minimal determinate rank for this observation (e.g. Brassica oleracea var. italica for broccoli). Return a genus-level name only when species determination is genuinely impossible from the image — in that case, return the genus name alone without any "sp." suffix. Never fabricate or guess names absent from taxonomic databases. 13) life_stage semantics (Darwin Core lifeStage): 'egg' = unhatched egg or egg mass; 'larva' = pre-metamorphic stage including caterpillar, grub, maggot, naiad, and tadpole; 'pupa' = chrysalis, cocoon, or pupal case in holometabolous insects; 'nymph' = hemimetabolous immature insect (grasshoppers, true bugs, dragonfly naiads) resembling the adult form but lacking functional wings; 'juvenile' = post-metamorphic immature that broadly resembles the adult; 'subadult' = nearly adult individual retaining visible juvenile morphological features such as immature plumage, fading spot patterns, or undeveloped secondary sexual characteristics; 'adult' = sexually mature individual; 'seedling' = plant from germination through first true leaf stage; 'sapling' = established juvenile woody plant prior to first reproduction; 'unknown' only when life stage is genuinely indeterminate from the available image. 14) reproductive_condition semantics (Darwin Core reproductiveCondition): Apply strictly to the primary subject only. 'flowering' = one or more open flowers visible; 'fruiting' = ripe or unripe fruit bodies, berries, cones, or seed pods present; 'budding' = only unopened flower or leaf buds present with no open flowers; 'vegetative' = active growth with no reproductive structures observed; 'sporing' = visible spore-bearing structures such as sori on ferns, sporangia on mosses, or gills and pores on fungi; 'pregnant' = viviparous mammal with visible abdominal enlargement indicating embryo development; 'gravid' = oviparous fish, reptile, or invertebrate carrying mature eggs internally; 'mating' = direct copulation or mating behaviour actively observed; 'spawning' = aquatic broadcast spawning event observed; 'nesting' = active nest construction, egg brooding, or chick incubation observed; 'dormant' = seasonal dormancy evidenced by leaf drop, torpor, or aestivation; 'not_applicable' when reproductive state is biologically indeterminate, not visible, or the taxon lacks discrete reproductive states. 15) ecology_type semantics: 'wild' = organism in natural or semi-natural habitat with no evidence of human introduction or intensive management; 'urban' = organism in human-modified landscape including gardens, parks, roadside verges, buildings, or agricultural margins; 'domesticated' = captive animal, actively cultivated plant, selectively bred variety, or farmed organism. 16) individual_count precision (Darwin Core individualCount): Count only visually distinct, spatially separate individuals of the primary species within the image frame. Estimate for partially visible groups at frame edges. For colonial organisms, clonal mats, or dense aggregations where individual organism boundaries cannot be reliably resolved — such as coral colonies, lichen thalli, dense grass swards, or ant colonies — return null.`;

// Shared schema properties present in both the biological and non-biological branches.
// Extracted to a factory function so both branches reference identical field definitions
// without duplication. Called at schema-build time (module scope, warm isolate cached).
const sharedProperties = (): Record<string, ResponseSchema> => ({
  extracted_visual_traits: {
    type: SchemaType.ARRAY,
    items: { type: SchemaType.STRING },
    description:
      "Extract exactly 3 distinct physical or structural traits observed in the image (e.g. 'smooth texture', 'embedded in concrete', 'green leaves').",
  },
  ai_reasoning: {
    type: SchemaType.STRING,
    description:
      "A 1-3 sentence intelligence analysis breaking down the exact reasoning behind this identification. Detail the specific physical attributes, structural nuances, and visual evidence extracted from the image that substantiate this classification.",
  },
  is_biological_subject: { type: SchemaType.BOOLEAN },
  is_live_capture: { type: SchemaType.BOOLEAN },
  confidence_score: {
    type: SchemaType.NUMBER,
    description:
      "A value between 0.0 and 1.0 representing AI confidence in the primary identification.",
  },
  candidates: {
    type: SchemaType.ARRAY,
    items: {
      type: SchemaType.OBJECT,
      properties: {
        scientific_name: { type: SchemaType.STRING },
        confidence_score: { type: SchemaType.NUMBER },
      },
      required: ["scientific_name", "confidence_score"],
    },
    description:
      "ALWAYS provide exactly 2 alternative species candidates that could plausibly match the image. Each must be a genuinely distinct species — not a subspecies or synonym of the primary identification.",
  },
  image_quality: {
    type: SchemaType.OBJECT,
    properties: {
      sharpness: { type: SchemaType.INTEGER },
      framing: { type: SchemaType.INTEGER },
      diagnostic_utility: { type: SchemaType.INTEGER },
      overall_score: { type: SchemaType.INTEGER },
    },
    required: ["sharpness", "framing", "diagnostic_utility", "overall_score"],
    description:
      "Photographic quality scores for encyclopedic reference use. sharpness 1–10: focus and motion blur. framing 1–10: subject fully visible and isolated. diagnostic_utility 1–10: taxonomic features clearly displayed. overall_score 0–100: holistic reference quality.",
  },
});

// Required fields common to both branches.
const SHARED_REQUIRED = [
  "is_biological_subject",
  "is_live_capture",
  "extracted_visual_traits",
  "ai_reasoning",
  "confidence_score",
  "image_quality",
  "candidates",
] as const;

// Branch 1: biological subject (is_biological_subject = true).
// All taxonomy-relevant fields are required. individual_count is nullable because
// it may be impossible to estimate in occluded or crowded scenes.
const biologicalBranch = (): ResponseSchema => ({
  type: SchemaType.OBJECT,
  properties: {
    ...sharedProperties(),
    scientific_name: {
      type: SchemaType.STRING,
      description: "Formally accepted binomial scientific name.",
    },
    common_name: {
      type: SchemaType.STRING,
      description:
        "Most specific, commonly recognized English name in Title Case. Ensure words are spaced correctly (e.g., 'Red-tailed Hawk').",
    },
    ecology_type: {
      type: SchemaType.STRING,
      format: "enum",
      enum: ["wild", "urban", "domesticated", "unknown"],
    },
    is_invasive: { type: SchemaType.BOOLEAN },
    life_stage: {
      type: SchemaType.STRING,
      format: "enum",
      enum: [
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
      ],
    },
    reproductive_condition: {
      type: SchemaType.STRING,
      format: "enum",
      enum: [
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
      ],
    },
    individual_count: {
      type: SchemaType.INTEGER,
      nullable: true,
      description:
        "Number of distinct individuals of the primary species visible. Null when impossible to estimate.",
    },
    ecological_interactions: {
      type: SchemaType.ARRAY,
      items: { type: SchemaType.STRING },
      description:
        "Describe active interactions with other biological organisms visible in the frame.",
    },
  },
  required: [
    ...SHARED_REQUIRED,
    "scientific_name",
    "common_name",
    "ecology_type",
    "is_invasive",
    "life_stage",
    "reproductive_condition",
    "ecological_interactions",
  ],
});

// Branch 2: non-biological subject (is_biological_subject = false).
// Biology-specific fields (ecology_type, is_invasive, life_stage, etc.) are absent
// from the schema entirely — the model does not output them, saving candidate tokens.
// scientific_name and common_name are nullable: present for identifiable geological
// subjects (rocks, minerals), absent for generic debris or non-natural objects.
const nonBiologicalBranch = (): ResponseSchema => ({
  type: SchemaType.OBJECT,
  properties: {
    ...sharedProperties(),
    scientific_name: {
      type: SchemaType.STRING,
      nullable: true,
      description:
        "Scientific or mineralogical name for identifiable geological specimens. Null for generic debris or man-made objects.",
    },
    common_name: {
      type: SchemaType.STRING,
      nullable: true,
      description:
        "Recognised English name for identifiable geological or mineralogical subjects. Null for generic debris or man-made objects.",
    },
  },
  required: [...SHARED_REQUIRED],
});

// Schema cache keyed by diagnosticTrigger so warm isolate re-use avoids repeated
// object construction across requests. Two entries maximum (flash=0.95, pro=0.85).
// The trigger value does not currently affect schema shape but the cache is keyed
// by it for forward compatibility if per-tier schema divergence is introduced later.
const schemaCache = new Map<number, ResponseSchema>();

export const getMerianResponseSchema = (
  diagnosticTrigger: number,
): ResponseSchema => {
  if (schemaCache.has(diagnosticTrigger)) {
    return schemaCache.get(diagnosticTrigger)!;
  }

  // anyOf lets the model pick the correct branch based on is_biological_subject.
  // The biological branch requires all biology-specific fields; the non-biological
  // branch omits them entirely. This eliminates the null-padding of ~8 fields on
  // every non-bio scan (rocks, debris, etc.) and gives the model explicit signal
  // about which fields are valid in each context, improving structured output fidelity.
  const schema: ResponseSchema = {
    anyOf: [biologicalBranch(), nonBiologicalBranch()],
  };

  schemaCache.set(diagnosticTrigger, schema);
  return schema;
};
