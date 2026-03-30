import {
  SchemaType,
  ResponseSchema,
} from "https://esm.sh/@google/generative-ai@0.24.1";

export const systemInstruction = `Identify biology precisely. 1) Liveness: fossils, pressed/preserved/dried specimens are is_biological_subject=true with is_live_capture=false — identify to species level. Non-biological objects (rocks, buildings, food, debris, shadows, cracks) are is_biological_subject=false. 2) Evaluate is_invasive based on GPS. 3) common_name must be maximally specific in Title Case. 4) CRITICAL: Evaluate all provided images together. 5) Multiple species → identify ONE primary. 6) is_biological_subject=false → OMIT is_invasive, ecology_type, scientific_name, colors, regional_status_rationale, common_name. 7) Micro-CoT & Pareidolia Avoidance: You MUST extract 3 structural observations in extracted_visual_traits BEFORE determining is_biological_subject or scientific_name. Actively reject optical illusions, pareidolia, and inanimate objects mimicking biology (e.g., cracks looking like snakes). Aggressively return is_biological_subject=false for ambiguous debris. 8) If the primary subject is actively interacting with another biological organism, describe the interaction and name the secondary organism in ecological_interactions. 9) Estimate the number of distinct individuals of the primary species visible in the frame for individual_count.`;

const schemaProperties: Record<string, ResponseSchema> = {
  is_biological_subject: { type: SchemaType.BOOLEAN },
  is_live_capture: { type: SchemaType.BOOLEAN },
  ecology_type: {
    type: SchemaType.STRING,
    format: "enum",
    enum: ["wild", "urban", "domesticated", "unknown"],
  },
  scientific_name: { type: SchemaType.STRING },
  confidence_score: { type: SchemaType.NUMBER },
  blur_score: { type: SchemaType.NUMBER },
  is_invasive: { type: SchemaType.BOOLEAN },
  ai_reasoning: {
    type: SchemaType.STRING,
    description:
      "A 1-3 sentence intelligence analysis breaking down the exact reasoning behind this identification. Detail the specific physical attributes, structural nuances, and visual evidence extracted from the image that substantiate this classification.",
  },
  extracted_visual_traits: {
    type: SchemaType.ARRAY,
    items: { type: SchemaType.STRING },
    description: "Extract exactly 3 distinct physical or structural traits observed in the image (e.g. 'smooth texture', 'embedded in concrete', 'green leaves').",
  },
  common_name: {
    type: SchemaType.STRING,
    description:
      "Most specific, commonly recognized English name in Title Case. Ensure words are spaced correctly (e.g., 'Red-tailed Hawk').",
  },
  life_stage: {
    type: SchemaType.STRING,
    format: "enum",
    enum: ["egg", "larva", "pupa", "nymph", "juvenile", "subadult", "adult", "seedling", "sapling", "unknown"],
  },
  reproductive_condition: {
    type: SchemaType.STRING,
    format: "enum",
    enum: ["flowering", "fruiting", "budding", "vegetative", "sporing", "pregnant", "gravid", "mating", "spawning", "nesting", "dormant", "not_applicable"],
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
      "Only populate when genuinely uncertain between multiple species (i.e. confidence_score is low). Include up to 2 alternative species you seriously considered, with your estimated confidence for each. Omit entirely for clear, confident identifications.",
  },
};

export const merianResponseSchema: ResponseSchema = {
  type: SchemaType.OBJECT,
  properties: schemaProperties,
  required: [
    "is_biological_subject",
    "is_live_capture",
    "extracted_visual_traits",
    "ai_reasoning",
    "confidence_score",
    "blur_score",
  ],
};
