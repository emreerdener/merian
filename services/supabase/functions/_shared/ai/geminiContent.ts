import {
  type GenerateContentParameters,
  type Schema,
  Type,
} from "@google/genai";
import type { SpeciesContentAIRequest } from "./contracts.ts";
import { normalizeTaxonomyValue } from "../taxonomy.ts";

const SchemaType = Type;
type ContentProjection = Pick<GenerateContentParameters, "contents"> & {
  systemInstruction: string;
  responseSchema: Schema;
};

/** Native Gemini projections; strings and schemas preserve the legacy helpers. */
export function buildGeminiContent(
  request: SpeciesContentAIRequest,
): ContentProjection {
  switch (request.task) {
    case "species_overview":
      return overview(request.scientificName, request.locale);
    case "lookalikes":
      return lookalikes(request.scientificName, request.taxonomy);
    case "group_tags":
      return groupTags(request.scientificName);
  }
}
function overview(scientificName: string, locale: string): ContentProjection {
  const systemInstruction = `# Role
You are a world-class encyclopedic biologist and taxonomist.

# Task
Given a species scientific name, provide the following data fields: taxonomy, habitat description, hazard classification, generalized physical colors, IUCN conservation status, and global distribution.

# Rules
- **Conciseness:** Keep all text descriptions concise and factual.
- **Locale:** ALL text responses (habitat_description) MUST be returned in the following ISO language locale: ${locale}.
- **Accuracy:** Base all fields on authoritative sources (GBIF, IUCN Red List, Catalogue of Life). Never fabricate data.`;
  const cacheSchema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      taxonomy: {
        type: SchemaType.OBJECT,
        properties: {
          kingdom: { type: SchemaType.STRING },
          phylum: { type: SchemaType.STRING },
          class: { type: SchemaType.STRING },
          order: { type: SchemaType.STRING },
          family: { type: SchemaType.STRING },
          genus: { type: SchemaType.STRING },
        },
        required: ["kingdom", "phylum", "class", "order", "family", "genus"],
      },
      iucn_red_list_status: {
        type: SchemaType.STRING,
        enum: [
          "not_evaluated",
          "data_deficient",
          "least_concern",
          "near_threatened",
          "vulnerable",
          "endangered",
          "critically_endangered",
          "extinct_in_the_wild",
          "extinct",
        ],
      },
      habitat_description: { type: SchemaType.STRING },
      hazard_type: {
        type: SchemaType.STRING,
        enum: ["none", "poisonous", "venomous", "allergenic", "irritant"],
        description: "Generalized hazard type for this species.",
      },
      colors: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description:
          "1-3 generalized physical colors that typically identify this species.",
      },
    },
    required: [
      "taxonomy",
      "iucn_red_list_status",
      "habitat_description",
      "hazard_type",
      "colors",
    ],
  };
  return {
    systemInstruction,
    contents: [{
      role: "user",
      parts: [{ text: `Generate metadata for the species: ${scientificName}` }],
    }],
    responseSchema: cacheSchema as unknown as Schema,
  };
}

function lookalikes(
  scientificName: string,
  taxonomy: Extract<
    SpeciesContentAIRequest,
    { task: "lookalikes" }
  >["taxonomy"],
): ContentProjection {
  const normalizedKingdom = normalizeTaxonomyValue(taxonomy?.kingdom);
  const normalizedClass = normalizeTaxonomyValue(taxonomy?.class);
  const normalizedOrder = normalizeTaxonomyValue(taxonomy?.order);
  const normalizedFamily = normalizeTaxonomyValue(taxonomy?.family);

  // Build a taxonomic context string so Flash is grounded in the correct kingdom/class/order.
  // Without this, the model can hallucinate cross-kingdom suggestions (e.g. plants for insects).
  const taxonomicContext = [
    normalizedKingdom ? `Kingdom: ${normalizedKingdom}` : null,
    normalizedClass ? `Class: ${normalizedClass}` : null,
    normalizedOrder ? `Order: ${normalizedOrder}` : null,
    normalizedFamily ? `Family: ${normalizedFamily}` : null,
  ]
    .filter(Boolean)
    .join(", ");

  const taxonomyLine = taxonomicContext
    ? `\n\nThe species belongs to: ${taxonomicContext}. ALL lookalikes MUST belong to the same kingdom AND the same order or family as the primary species. If no suitable lookalikes exist at that rank, return fewer entries rather than suggesting unrelated species.`
    : "";

  const systemInstruction = `# Role
You are a world-class field biologist specializing in species misidentification and visual lookalikes.

# Task
Given a species scientific name, identify up to 3 species that a non-expert field observer could plausibly misidentify it as based purely on visual appearance in the field.${taxonomyLine}

For each lookalike, provide the exact formally recognized scientific name, the widely recognised English common name, a concise explanation of the visual confusion, the concrete visible traits shared by both species, and a calibrated relation confidence.

# Rules
1. **Taxonomic Constraint:** Every lookalike MUST be from the same taxonomic order or family as the primary species — never suggest species from a different order.
2. **Visual Similarity:** Lookalikes must be genuinely visually similar in the field (similar flower shape, leaf morphology, growth habit, plumage, etc.) — not merely distantly related.
3. **Name Accuracy:** Never hallucinate scientific names. Every entry must be a verified, extant species recognized by GBIF or Catalogue of Life.
4. **No Padding:** If fewer than 3 genuine same-order lookalikes exist, return only the valid ones — do not pad with unrelated species.
5. **No Self-Reference:** Do not return the primary species itself as a lookalike.
6. **Explainability:** Reasons must be species-level visual explanations, not user-specific observations. Do not mention scans, photos, people, locations, dates, or field notes.
7. **Confidence:** Confidence is relation quality from 0.0 to 1.0, where 1.0 means a very strong field-confusion relationship and 0.5 means weak but plausible.`;
  const schema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      similar_species: {
        type: SchemaType.ARRAY,
        items: {
          type: SchemaType.OBJECT,
          properties: {
            scientific_name: { type: SchemaType.STRING },
            common_name: { type: SchemaType.STRING },
            reason: {
              type: SchemaType.STRING,
              description:
                "One concise sentence explaining why field observers may confuse the two species visually.",
            },
            visual_traits: {
              type: SchemaType.ARRAY,
              items: { type: SchemaType.STRING },
              description:
                "Two to four concrete shared visual traits, such as wing pattern, flower shape, bark texture, silhouette, or growth habit.",
            },
            confidence: {
              type: SchemaType.NUMBER,
              description:
                "0.0 to 1.0 confidence that this is a strong visual lookalike relation.",
            },
          },
          required: [
            "scientific_name",
            "common_name",
            "reason",
            "visual_traits",
            "confidence",
          ],
        },
        description:
          `Up to 3 closely related but genuinely visually similar lookalike species from the same kingdom${
            normalizedClass ? ` and class (${normalizedClass})` : ""
          }, each with a real, formally recognized scientific name, English common name, visual reason, shared traits, and relation confidence.`,
      },
    },
    required: ["similar_species"],
  };

  const userPrompt = taxonomicContext
    ? `Identify up to 3 genuine lookalike species for: ${scientificName} (${taxonomicContext})`
    : `Identify up to 3 genuine lookalike species for: ${scientificName}`;
  return {
    systemInstruction,
    contents: [{ role: "user", parts: [{ text: userPrompt }] }],
    responseSchema: schema as unknown as Schema,
  };
}

function groupTags(scientificName: string): ContentProjection {
  const systemInstruction =
    'You are a world-class biologist. Given a species scientific name, return 1–5 categorical group labels ordered from most broad to most specific (e.g. ["animal", "bird", "songbird", "warbler"]). Use plain lowercase English nouns only. Omit proper names and scientific names.';
  const schema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      group_tags: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description: "1–5 categorical group labels, broad to specific.",
      },
    },
    required: ["group_tags"],
  };
  return {
    systemInstruction,
    contents: [{
      role: "user",
      parts: [{ text: `Group tags for: ${scientificName}` }],
    }],
    responseSchema: schema as unknown as Schema,
  };
}
