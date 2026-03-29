import {
  SchemaType,
  ResponseSchema,
} from "https://esm.sh/@google/generative-ai@0.24.1";

export const systemInstruction = `Identify biology precisely. 1) Liveness: fossils, pressed/preserved/dried specimens are is_biological_subject=true with is_live_capture=false — identify to species level. Non-biological objects (rocks, buildings, food) are is_biological_subject=false. 2) Evaluate is_invasive based on GPS. 3) common_name must be maximally specific in Title Case. 4) CRITICAL: Evaluate all provided images together. 5) Multiple species → identify ONE primary. 6) is_biological_subject=false → OMIT is_invasive, ecology_type, scientific_name, colors, regional_status_rationale, common_name. 7) Confidence Calibration & Holistic Verification Rule: Do not assign a high confidence_score based solely on localized features. Before finalizing your score, you MUST evaluate the plant's holistic growth habit and environmental context. 8) If the primary subject is actively interacting with another biological organism (e.g., pollinating a flower, eating a leaf, parasitizing a host), briefly describe the interaction and name the secondary organism in ecological_interactions. 9) Estimate the number of distinct individuals of the primary species visible in the frame for individual_count. If a massive swarm/cluster, provide a conservative estimated integer.`;

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
      "A 2-3 sentence intelligence analysis breaking down the exact reasoning behind this identification. Detail the specific physical attributes, structural nuances, and visual evidence extracted from the image that substantiate this classification.",
  },
  common_name: {
    type: SchemaType.STRING,
    description:
      "Most specific, commonly recognized English name in Title Case. Ensure words are spaced correctly (e.g., 'Red-tailed Hawk').",
  },
  life_stage: {
    type: SchemaType.STRING,
    format: "enum",
    enum: ["egg", "larva", "juvenile", "adult", "unknown"],
  },
  reproductive_condition: {
    type: SchemaType.STRING,
    format: "enum",
    enum: ["flowering", "fruiting", "sporing", "dormant", "not_applicable"],
  },
  individual_count: {
    type: SchemaType.INTEGER,
  },
  ecological_interactions: {
    type: SchemaType.ARRAY,
    items: { type: SchemaType.STRING },
  },
};

export const merianResponseSchema: ResponseSchema = {
  type: SchemaType.OBJECT,
  properties: schemaProperties,
  required: [
    "is_biological_subject",
    "is_live_capture",
    "ai_reasoning",
    "confidence_score",
    "blur_score",
  ],
};
