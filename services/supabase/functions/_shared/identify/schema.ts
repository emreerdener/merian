import {
  Schema,
  Type,
} from "https://esm.sh/@google/genai@1.0.0";

// Alias for backward compat within this file
type ResponseSchema = Schema;
const SchemaType = Type;

export const getSystemInstruction = (_diagnosticTrigger: number) =>
  `# Role
You are an expert encyclopedic field-guide biologist and taxonomist. Your task is to identify biological subjects precision and structure the output according to strict taxonomic and ecological standards.

# Core Directives
- **Holistic Evaluation:** CRITICAL: Evaluate all provided images together as a single observation.
- **Primary Subject:** If multiple species are present, identify ONE primary biological subject.
- **Micro-CoT & Pareidolia Avoidance:** Actively reject optical illusions, pareidolia, and inanimate objects mimicking biology (e.g., cracks looking like snakes). Aggressively return \`is_biological_subject=false\` for ambiguous debris. You MUST extract 3 structural observations in \`extracted_visual_traits\` BEFORE determining \`is_biological_subject\` or \`scientific_name\`.

# Subject Liveness & Status
- **Biological Subjects:** Fossils, pressed/preserved/dried specimens are \`is_biological_subject=true\` with \`is_live_capture=false\` — identify these to the species level.
- **Non-Biological Objects:** Rocks, buildings, food, debris, shadows, and cracks are \`is_biological_subject=false\`. 
- **Geological Exceptions:** For geological subjects (rocks, minerals), you MUST still provide \`common_name\` and \`scientific_name\` if identifiable. Omit these for generic debris.
- **Conditional Formatting:** If \`is_biological_subject=false\`, you MUST omit: \`is_invasive\`, \`ecology_type\`, \`life_stage\`, \`reproductive_condition\`, \`individual_count\`, and \`ecological_interactions\`.

# Identification Rules
1. **Nomenclature:** \`common_name\` must be maximally specific in Title Case.
2. **Scientific Name:** \`scientific_name\` MUST be the currently accepted binomial recognized by GBIF, ITIS, or Catalogue of Life. 
   - Never return author citations (e.g., omit "(Linnaeus, 1758)"), hybrid markers (×), or infraspecific ranks unless it is the minimal determinate rank (e.g., *Brassica oleracea var. italica*). 
   - Return a genus-level name alone (without "sp.") ONLY when species determination is impossible. Never fabricate names.
3. **Invasiveness:** Evaluate \`is_invasive\` based on the provided GPS coordinates.
4. **Interactions:** If the primary subject is actively interacting with another biological organism, describe it and name the secondary organism in \`ecological_interactions\`.
5. **Counting:** Estimate the number of visually distinct, spatially separate individuals of the primary species in the frame for \`individual_count\`. Estimate for edges. Return \`null\` for colonial organisms/dense aggregations (coral, lichen, ant colonies) where boundaries cannot be resolved.

# Disambiguation & Confidence Calibration
- **Tiebreakers:** When multiple species are visually equally plausible, use GPS location and current month as a tiebreaker. Prefer the species with higher documented observation frequency in that region/season.
- **Handling Uncertainty:** Express genuine uncertainty through a lower \`confidence_score\` and populated \`candidates\` array rather than hallucinating or alternating primary identifications.
- **Confidence Scoring:** \`confidence_score\` must be derived *solely* from morphological features visible in the image. Local abundance or seasonal expectation does NOT raise confidence. Most field photographs warrant a score of 0.70–0.88. Reserve ≥0.90 ONLY when the image displays unambiguous diagnostic features that visibly exclude all similar species.

# Output Data Definitions

## Candidates Array
You MUST always populate exactly 2 alternative species in the \`candidates\` array.
- Choose candidates that share the most traits from \`extracted_visual_traits\` with the primary ID. Prioritize visually confusable species over merely taxonomically related ones.
- **Distinguishing Feature:** For each candidate, provide the single most important observable morphological difference that separates it from your primary ID. State this as a concise clause referencing a specific visible trait (e.g., "cap margin lacks striations present on primary"). Do NOT repeat the species name here.

## Image Quality
Score the image as a reference photo across these dimensions:
- **sharpness:** (1–10) Focus and absence of motion blur.
- **framing:** (1–10) Subject fully in frame and isolated from chaotic background.
- **diagnostic_utility:** (1–10) Taxonomic identification features clearly displayed (e.g., leaf venation, plumage, bark texture).
- **overall_score:** (0–100) Holistic reference quality synthesizing all three dimensions.

## Darwin Core Semantics Dictionary
Output fields must align semantically with the Darwin Core data standard:

**life_stage:**
- \`egg\`: unhatched egg or egg mass
- \`larva\`: pre-metamorphic stage (caterpillar, grub, maggot, naiad, tadpole)
- \`pupa\`: chrysalis, cocoon, or pupal case
- \`nymph\`: hemimetabolous immature insect (lacking functional wings)
- \`juvenile\`: post-metamorphic immature resembling adult
- \`subadult\`: nearly adult retaining visible juvenile features
- \`adult\`: sexually mature individual
- \`seedling\`: plant from germination through first true leaf
- \`sapling\`: established juvenile woody plant prior to reproduction
- \`unknown\`: genuinely indeterminate from image

**reproductive_condition:** (Apply strictly to primary subject)
- \`flowering\`: one/more open flowers visible
- \`fruiting\`: ripe/unripe fruit, berries, cones, seed pods 
- \`budding\`: unopened flower/leaf buds only
- \`vegetative\`: active growth, no reproductive structures
- \`sporing\`: visible spore-bearing structures (sori, gills, pores)
- \`pregnant\`: viviparous mammal with visible abdominal enlargement
- \`gravid\`: oviparous animal carrying mature eggs internally
- \`mating\`: direct copulation/mating behaviour observed
- \`spawning\`: aquatic broadcast spawning event
- \`nesting\`: active nest construction, egg brooding, chick incubation
- \`dormant\`: seasonal dormancy (leaf drop, torpor, aestivation)
- \`not_applicable\`: indeterminate, not visible, or taxon lacks states

**ecology_type:**
- \`wild\`: natural/semi-natural habitat, no intensive management
- \`urban\`: human-modified landscape (gardens, parks, roadsides, buildings)
- \`domesticated\`: captive animal, cultivated plant, farmed organism
`;

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
      "Calibrated confidence in the primary identification (0.0–1.0). " +
      "ANCHORS: " +
      "≥0.95 = key diagnostic features are unambiguously visible in the image AND no visually confusable species shares those exact features in the same region and season; " +
      "0.80–0.94 = confident but one or more similar species cannot be definitively ruled out from this image alone; " +
      "0.60–0.79 = probable identification, multiple visually similar species remain plausible; " +
      "<0.60 = uncertain, image lacks sufficient diagnostic detail for reliable species-level identification. " +
      "CRITICAL: base confidence ONLY on morphological features visible in the image. " +
      "NEVER inflate it because a species is locally common, seasonally expected, or habitat-appropriate — those factors resolve the primary identification but do not raise confidence. " +
      "Most field photographs of common species warrant a score of 0.70–0.88.",
  },
  candidates: {
    type: SchemaType.ARRAY,
    items: {
      type: SchemaType.OBJECT,
      properties: {
        scientific_name: { type: SchemaType.STRING },
        confidence_score: { type: SchemaType.NUMBER },
        distinguishing_feature: {
          type: SchemaType.STRING,
          description:
            "The single most important visual feature that separates this candidate from the primary identification. Must reference a specific trait from extracted_visual_traits or a directly observable morphological difference (e.g. 'cap margin lacks striations', 'wing bars absent', 'leaf base asymmetric'). One concise clause — do not repeat the species name.",
        },
      },
      required: ["scientific_name", "confidence_score", "distinguishing_feature"],
    },
    description:
      "ALWAYS provide exactly 2 alternative species candidates grounded in the extracted_visual_traits. Choose candidates that share the most observed traits with the primary identification — not just taxonomically related species. For each, distinguishing_feature must name the specific observable difference that rules it in or out.",
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

  // Flat schema: all fields in one object, biology-specific ones nullable.
  // Previously used anyOf [biologicalBranch, nonBiologicalBranch] to let Gemini
  // pick the right field set, but anyOf at the responseSchema root can cause the
  // Gemini API to reject the entire request with a structured-output validation
  // error before inference starts — the root schema must be a plain OBJECT.
  // The system instruction already tells the model to omit biology fields for
  // non-biological subjects (is_biological_subject=false), so the flat schema
  // produces equivalent output quality with universal API compatibility.
  const schema: ResponseSchema = {
    type: SchemaType.OBJECT,
    properties: {
      ...sharedProperties(),
      scientific_name: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Formally accepted binomial scientific name. Required for biological subjects and identifiable geological specimens. Null for unidentifiable non-natural objects.",
      },
      common_name: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Most specific, commonly recognized English name in Title Case. Null for unidentifiable non-natural objects.",
      },
      ecology_type: {
        type: SchemaType.STRING,
        format: "enum",
        enum: ["wild", "urban", "domesticated", "unknown"],
        nullable: true,
        description: "Biological subjects only. Null for non-biological subjects.",
      },
      is_invasive: {
        type: SchemaType.BOOLEAN,
        nullable: true,
        description: "Biological subjects only. Null for non-biological subjects.",
      },
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
        nullable: true,
        description: "Biological subjects only. Null for non-biological subjects.",
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
        nullable: true,
        description: "Biological subjects only. Null for non-biological subjects.",
      },
      individual_count: {
        type: SchemaType.INTEGER,
        nullable: true,
        description:
          "Number of distinct individuals of the primary species visible. Null when impossible to estimate or for non-biological subjects.",
      },
      ecological_interactions: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        nullable: true,
        description:
          "Active interactions with other biological organisms visible in the frame. Null for non-biological subjects.",
      },
    },
    required: [...SHARED_REQUIRED],
  };

  schemaCache.set(diagnosticTrigger, schema);
  return schema;
};
