import {
  Schema,
  Type,
} from "https://esm.sh/@google/genai@1.0.0";
import { User } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createFlashModel, extractJson } from "./gemini.ts";
import { trackPostHogEvent } from "./posthog.ts";

// Alias for backward compat within this file
type ResponseSchema = Schema;
const SchemaType = Type;
// Local usage metadata shape — avoids coupling return types to the SDK's internal type name.
// thoughtsTokenCount is the new field exposed by @google/genai for thinking token accounting.
type UsageMetadata = {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  totalTokenCount?: number;
  thoughtsTokenCount?: number;
};

// --- ENCYCLOPEDIC DATA LOGIC --- //

export interface EncyclopedicData {
  taxonomy: {
    kingdom: string;
    phylum: string;
    class: string;
    order: string;
    family: string;
    genus: string;
  };
  iucn_red_list_status: string;
  habitat_description: string;
  hazard_type: string;
  colors: string[];
  usage?: UsageMetadata;
}

export async function fetchStaticEncyclopedicData(
  user: User,
  scientificName: string,
  locale = "en",
): Promise<EncyclopedicData> {
  const textModel = createFlashModel(
    `You are a world-class biologist. Provide encyclopedic identification traits, taxonomy, habitat, hazard classification, generalized physical colors, conservation status, and global distribution for the provided scientific name. Keep descriptions concise. ALL text responses (habitat_description) must be returned in the following ISO language locale: ${locale}.`,
    1500,
  );

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

  try {
    const result = await textModel.generateContent({
      contents: [
        {
          role: "user",
          parts: [
            { text: `Generate metadata for the species: ${scientificName}` },
          ],
        },
      ],
      config: {
        responseMimeType: "application/json",
        responseSchema: cacheSchema as unknown as ResponseSchema,
      },
    });

    const usage = result.usageMetadata;
    if (usage) {
      console.log(
        `Token Usage [Encyclopedic | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      trackPostHogEvent(user, "EncyclopedicLLMCompleted", {
        scientific_name: scientificName,
        llm_model: "gemini-2.5-flash",
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      }).catch((e) => console.error("PostHog EncyclopedicLLMCompleted failed:", e));
    }

    const extracted = extractJson<EncyclopedicData>(result.text ?? "");
    if (usage) {
      extracted.usage = usage;
    }
    return extracted;
  } catch (e) {
    console.error("Encyclopedic inference fallback failed:", e);
    return {
      taxonomy: {
        kingdom: "Unknown",
        phylum: "Unknown",
        class: "Unknown",
        order: "Unknown",
        family: "Unknown",
        genus: "Unknown",
      },
      iucn_red_list_status: "not_evaluated",
      habitat_description: "No habitat data available.",
      hazard_type: "none",
      colors: [],
    };
  }
}

// --- SIMILAR SPECIES LOGIC --- //

export interface SimilarSpeciesEntry {
  scientific_name: string;
  common_name: string | null;
}

export interface SpeciesTaxonomy {
  kingdom?: string | null;
  class?: string | null;
  order?: string | null;
  family?: string | null;
}

export async function fetchSimilarSpecies(
  user: User,
  scientificName: string,
  taxonomy?: SpeciesTaxonomy | null,
): Promise<{ similar_species: SimilarSpeciesEntry[]; usage?: UsageMetadata } | null> {
  // Build a taxonomic context string so Flash is grounded in the correct kingdom/class/order.
  // Without this, the model can hallucinate cross-kingdom suggestions (e.g. plants for insects).
  const taxonomicContext = [
    taxonomy?.kingdom ? `Kingdom: ${taxonomy.kingdom}` : null,
    taxonomy?.class ? `Class: ${taxonomy.class}` : null,
    taxonomy?.order ? `Order: ${taxonomy.order}` : null,
    taxonomy?.family ? `Family: ${taxonomy.family}` : null,
  ]
    .filter(Boolean)
    .join(", ");

  const taxonomyLine = taxonomicContext
    ? ` The species belongs to: ${taxonomicContext}. ALL lookalikes MUST belong to the same kingdom AND the same order or family as the primary species. If no suitable lookalikes exist at that rank, return fewer entries rather than suggesting unrelated species.`
    : "";

  const model = createFlashModel(
    `You are a world-class biologist. Given a species scientific name, identify up to 3 most commonly confused lookalike species that a field observer might misidentify it as.${taxonomyLine} For each lookalike, provide the exact, formally recognized scientific name and widely recognised English common name. CRITICAL RULES: 1) Never hallucinate scientific names; every lookalike must be a verified, real species. 2) Every lookalike must be from the same taxonomic order or family as the primary species. 3) Lookalikes must be genuinely visually similar. 4) If fewer than 3 genuine lookalikes exist, return only the valid ones. Do not invent species to fill the array.`,
    300,
  );

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
          },
          required: ["scientific_name", "common_name"],
        },
        description:
          `Up to 3 closely related but genuinely visually similar lookalike species from the same kingdom${taxonomy?.class ? ` and class (${taxonomy.class})` : ""}, each with a real, formally recognized scientific name and English common name.`,
      },
    },
    required: ["similar_species"],
  };

  const userPrompt = taxonomicContext
    ? `Identify up to 3 genuine lookalike species for: ${scientificName} (${taxonomicContext})`
    : `Identify up to 3 genuine lookalike species for: ${scientificName}`;

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: userPrompt }],
        },
      ],
      config: {
        responseMimeType: "application/json",
        responseSchema: schema as unknown as ResponseSchema,
      },
    });
    const usage = result.usageMetadata;
    if (usage) {
      console.log(
        `Token Usage [SimilarSpecies | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      trackPostHogEvent(user, "SimilarSpeciesLLMCompleted", {
        scientific_name: scientificName,
        llm_model: "gemini-2.5-flash",
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      }).catch((e) => console.error("PostHog SimilarSpeciesLLMCompleted failed:", e));
    }
    const raw = extractJson<{
      similar_species: Array<{ scientific_name: string; common_name?: string }>;
    }>(result.text ?? "");
    const normalized: { similar_species: SimilarSpeciesEntry[]; usage?: UsageMetadata } = {
      similar_species: (raw.similar_species ?? []).map((e) => ({
        scientific_name: e.scientific_name,
        common_name: e.common_name || null,
      })),
    };
    if (usage) normalized.usage = usage;
    return normalized;
  } catch (e) {
    console.error("fetchSimilarSpecies failed:", e);
    return null;
  }
}

// --- GROUP TAGS LOGIC --- //

export async function fetchGroupTags(
  user: User,
  scientificName: string,
): Promise<{ group_tags: string[] | null; usage?: UsageMetadata } | null> {
  const model = createFlashModel(
    'You are a world-class biologist. Given a species scientific name, return 1–5 categorical group labels ordered from most broad to most specific (e.g. ["animal", "bird", "songbird", "warbler"]). Use plain lowercase English nouns only. Omit proper names and scientific names.',
    100,
  );

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

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: `Group tags for: ${scientificName}` }],
        },
      ],
      config: {
        responseMimeType: "application/json",
        responseSchema: schema as unknown as ResponseSchema,
      },
    });

    const usage = result.usageMetadata;
    if (usage) {
      console.log(
        `Token Usage [GroupTags | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      trackPostHogEvent(user, "GroupTagsLLMCompleted", {
        scientific_name: scientificName,
        llm_model: "gemini-2.5-flash",
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      }).catch((e) => console.error("PostHog GroupTagsLLMCompleted failed:", e));
    }

    const parsed = extractJson<{ group_tags: string[] }>(
      result.text ?? "",
    );
    return { group_tags: parsed.group_tags ?? null, usage };
  } catch (e) {
    console.error("fetchGroupTags failed:", e);
    return null;
  }
}
