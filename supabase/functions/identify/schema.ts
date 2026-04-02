import {
  ResponseSchema,
  SchemaType,
} from "https://esm.sh/@google/generative-ai@0.24.1";

export const getSystemInstruction = (_diagnosticTrigger: number) =>
  `You are an expert encyclopedic field-guide biologist and taxonomist. Identify biology precisely. 1) Liveness: fossils, pressed/preserved/dried specimens are is_biological_subject=true with is_live_capture=false — identify to species level. Non-biological objects (rocks, buildings, food, debris, shadows, cracks) is_biological_subject=false. 2) Evaluate is_invasive based on GPS. 3) common_name must be maximally specific in Title Case. 4) CRITICAL: Evaluate all provided images together. 5) Multiple species → identify ONE primary. 6) is_biological_subject=false → OMIT is_invasive, ecology_type, life_stage, reproductive_condition, individual_count, ecological_interactions. You MUST provide common_name and scientific_name for geological subjects (e.g. rocks, minerals) if identifiable, but omit them for generic debris or non-natural objects. 7) Micro-CoT & Pareidolia Avoidance: You MUST extract 3 structural observations in extracted_visual_traits BEFORE determining is_biological_subject or scientific_name. Actively reject optical illusions, pareidolia, and inanimate objects mimicking biology (e.g., cracks looking like snakes). Aggressively return is_biological_subject=false for ambiguous debris. 8) If the primary subject is actively interacting with another biological organism, describe the interaction and name the secondary organism in ecological_interactions. 9) Estimate the number of distinct individuals of the primary species visible in the frame for individual_count. 10) Score the image as a potential encyclopedic field-guide reference photo in image_quality: sharpness (1–10, focus and absence of motion blur), framing (1–10, subject fully in frame and isolated from chaotic background), diagnostic_utility (1–10, taxonomic identification features clearly displayed — e.g. leaf venation, plumage, bark texture), and overall_score (0–100, holistic reference quality synthesizing all three dimensions). 11) Candidates: You MUST always populate the candidates array with exactly 2 alternative species that could plausibly match the image. These must be genuinely distinct alternatives — different species, not subspecies variants of your primary identification.`;

const getSchemaProperties = (
  _diagnosticTrigger: number,
): Record<string, ResponseSchema> => ({
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
  ecology_type: {
    type: SchemaType.STRING,
    format: "enum",
    enum: ["wild", "urban", "domesticated", "unknown"],
  },
  scientific_name: { type: SchemaType.STRING },
  confidence_score: {
    type: SchemaType.NUMBER,
    description:
      "A value between 0.0 and 1.0 representing AI confidence in the primary identification.",
  },
  is_invasive: { type: SchemaType.BOOLEAN },
  common_name: {
    type: SchemaType.STRING,
    description:
      "Most specific, commonly recognized English name in Title Case. Ensure words are spaced correctly (e.g., 'Red-tailed Hawk').",
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
  },
  ecological_interactions: {
    type: SchemaType.ARRAY,
    items: { type: SchemaType.STRING },
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

const schemaCache = new Map<number, ResponseSchema>();

export const getMerianResponseSchema = (
  diagnosticTrigger: number,
): ResponseSchema => {
  if (schemaCache.has(diagnosticTrigger)) {
    return schemaCache.get(diagnosticTrigger)!;
  }
  const schema: ResponseSchema = {
    type: SchemaType.OBJECT,
    properties: getSchemaProperties(diagnosticTrigger),
    required: [
      "is_biological_subject",
      "is_live_capture",
      "extracted_visual_traits",
      "ai_reasoning",
      "confidence_score",
      "image_quality",
      "candidates",
    ],
  };
  schemaCache.set(diagnosticTrigger, schema);
  return schema;
};
