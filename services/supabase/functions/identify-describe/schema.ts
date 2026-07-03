import { Schema, Type } from "npm:@google/genai@1.0.0";

type ResponseSchema = Schema;
const SchemaType = Type;

// ---------------------------------------------------------------------------
// System instruction — text-only identification path
// ---------------------------------------------------------------------------

export const getDescribeSystemInstruction = (): string =>
  `# Role
You are an expert field-guide biologist and taxonomist specializing in species identification from verbal observation descriptions. Your task is to identify the most likely biological subject from a structured text description provided by a user who observed but did not photograph the organism.

# Core Directives
- **Description-Based Reasoning:** You will receive a structured text description. There is NO photograph. Reason purely from the provided descriptors and any geographic or seasonal context supplied.
- **Extract Traits from Description:** extracted_visual_traits MUST be drawn from the description text itself — do not infer traits the user did not mention.
- **Geographic Tiebreakers:** Use GPS coordinates and current month to narrow the plausible species pool. Prefer species with high documented observation frequency in that region and season when multiple candidates are equally plausible from the description alone.
- **Invasiveness:** Evaluate \`is_invasive\`, \`invasive_status_region\`, \`invasive_rationale\`, and \`invasive_confidence\` as one location-aware assessment from the supplied GPS/coarse location, species identity, and ecological context. If location context is missing, return \`is_invasive=false\`, \`invasive_status_region="Unavailable"\`, explain the limitation in \`invasive_rationale\`, and use low or null \`invasive_confidence\`.
- **Honest Uncertainty:** Verbal descriptions are inherently ambiguous — a "brown bird perching on a tree" could be hundreds of species. Express genuine uncertainty through a lower confidence_score and a well-populated candidates array. Do NOT hallucinate specificity the description cannot support.

# Identification Rules
1. **Nomenclature:** common_name must be maximally specific in Title Case.
2. **Scientific Name:** Must be the currently accepted binomial from GBIF, ITIS, or Catalogue of Life. Return a genus-level name only when species determination is genuinely impossible from the description. Never fabricate names.
3. **is_live_capture:** ALWAYS return false — this is a recalled verbal describe, not a photographic capture.
4. **image_quality:** ALWAYS return { sharpness: 0, framing: 0, diagnostic_utility: 0, overall_score: 0 } — there is no image to score. This field exists only for schema parity with the vision path.
5. **extracted_visual_traits:** Extract the 3 most taxonomically significant descriptors directly from the observation description. These must be verbatim or closely paraphrased from what the user wrote, not inferred.
6. **Confidence Calibration:** Text-based identifications are inherently less precise than photographic ones. Anchors:
   - ≥0.85: Descriptor combination maps unambiguously to a single species in the given region and season (rare — requires highly distinctive traits like unique coloration pattern + size + behavior).
   - 0.60–0.84: Confident but multiple visually similar species remain plausible given the description.
   - 0.40–0.59: Probable identification, description lacks sufficient diagnostic detail.
   - <0.40: Highly uncertain — description is too generic for reliable species-level ID.
   Most descriptions warrant 0.45–0.75. Do NOT inflate confidence because a species is locally common.
7. **Sex:** Report sex only when the user's description contains diagnostic evidence for the primary subject. Never infer sex from species name, population tendency, or stereotypes. Never infer or report human sex/gender; use not_applicable for human subjects. Use cannot_determine when evidence is absent or non-diagnostic.

# Candidates Array
ALWAYS populate exactly 2 alternative species in the candidates array. For distinguishing_feature, name the specific descriptor from the user's description that the candidate would or would not match (e.g., "lacks the striped pattern described by user", "smaller than palm-sized as noted").

# Non-Biological Descriptions
If the description clearly refers to a non-biological subject (rock, building, vehicle), return is_biological_subject=false and omit biology-specific fields per the same rules as the vision path, including all invasive-status fields.

# Output Data Definitions

## Darwin Core Semantics
Use the same life_stage, reproductive_condition, sex, and ecology_type values as the vision path where determinable from the description.
`;

// ---------------------------------------------------------------------------
// Response schema — identical structure to the vision path for iOS parity
// ---------------------------------------------------------------------------

const sharedProperties = (): Record<string, ResponseSchema> => ({
  extracted_visual_traits: {
    type: SchemaType.ARRAY,
    items: { type: SchemaType.STRING },
    description:
      "Extract exactly 3 distinct traits from the observation description (e.g., 'brown coloration', 'palm-sized', 'perching on tree bark'). Must come directly from the user's description.",
  },
  ai_reasoning: {
    type: SchemaType.STRING,
    description:
      "1–3 sentence analysis of the identification reasoning. Reference the specific descriptors in the observation that support the identification and explain why they point to this species over the alternatives.",
  },
  is_biological_subject: { type: SchemaType.BOOLEAN },
  is_live_capture: {
    type: SchemaType.BOOLEAN,
    description: "Always false for describe descriptions.",
  },
  confidence_score: {
    type: SchemaType.NUMBER,
    description:
      "Calibrated confidence based solely on the description's diagnostic specificity (0.0–1.0). " +
      "ANCHORS: ≥0.85 = description maps unambiguously to one species in the given region/season; " +
      "0.60–0.84 = confident but similar species cannot be ruled out; " +
      "0.40–0.59 = probable, description lacks diagnostic detail; <0.40 = too generic for reliable ID. " +
      "Most descriptions warrant 0.45–0.75. NEVER inflate based on local abundance.",
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
            "The single most important difference between this candidate and the primary identification, phrased in terms of the user's description (e.g., 'lacks the spotted pattern user described').",
        },
      },
      required: [
        "scientific_name",
        "confidence_score",
        "distinguishing_feature",
      ],
    },
    description:
      "Always provide exactly 2 alternative species grounded in the observation description.",
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
      "Always return all zeros for describe descriptions — no image to score.",
  },
});

const SHARED_REQUIRED = [
  "is_biological_subject",
  "is_live_capture",
  "extracted_visual_traits",
  "ai_reasoning",
  "confidence_score",
  "image_quality",
  "candidates",
] as const;

let schemaCache: ResponseSchema | null = null;

export const getDescribeResponseSchema = (): ResponseSchema => {
  if (schemaCache) return schemaCache;

  schemaCache = {
    type: SchemaType.OBJECT,
    properties: {
      ...sharedProperties(),
      scientific_name: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Formally accepted binomial. Null for unidentifiable non-biological subjects.",
      },
      common_name: {
        type: SchemaType.STRING,
        nullable: true,
        description: "Most specific recognized English name in Title Case.",
      },
      ecology_type: {
        type: SchemaType.STRING,
        format: "enum",
        enum: ["wild", "urban", "domesticated", "unknown"],
        nullable: true,
      },
      is_invasive: { type: SchemaType.BOOLEAN, nullable: true },
      invasive_status_region: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Region label used for the invasive-status assessment, such as 'Austin, TX', 'Central Texas', or 'Unavailable'. Null for non-biological subjects.",
      },
      invasive_rationale: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "One concise sentence explaining the invasive-status assessment from the original description reasoning, location context, species identity, and ecological context. Null for non-biological subjects.",
      },
      invasive_confidence: {
        type: SchemaType.NUMBER,
        nullable: true,
        description:
          "Confidence from 0.0 to 1.0 for the invasive-status assessment, separate from identification confidence. Null when location evidence is insufficient or subject is non-biological.",
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
      },
      sex: {
        type: SchemaType.STRING,
        format: "enum",
        enum: [
          "female",
          "male",
          "hermaphrodite",
          "mixed",
          "cannot_determine",
          "not_applicable",
        ],
        nullable: true,
      },
      sex_confidence: { type: SchemaType.NUMBER, nullable: true },
      sex_evidence: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Short phrase naming the user-described evidence for sex. Null when unsupported.",
      },
      individual_count: { type: SchemaType.INTEGER, nullable: true },
    },
    required: [...SHARED_REQUIRED],
  };

  return schemaCache;
};
