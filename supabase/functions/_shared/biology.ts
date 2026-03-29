import {
  ResponseSchema,
  SchemaType,
  UsageMetadata,
} from "https://esm.sh/@google/generative-ai@0.24.1";
import { User } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createFlashModel, extractJson } from "./gemini.ts";
import { trackPostHogEvent } from "./posthog.ts";

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
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: cacheSchema as unknown as ResponseSchema,
      },
    });

    const usage = result.response.usageMetadata;
    if (usage) {
      console.log(
        `Token Usage [Encyclopedic | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      await trackPostHogEvent(user, "EncyclopedicLLMCompleted", {
        scientific_name: scientificName,
        llm_model: "gemini-2.5-flash",
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      });
    }

    const extracted = extractJson<EncyclopedicData>(result.response.text());
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

export async function fetchSimilarSpecies(
  user: User,
  scientificName: string,
) {
  const model = createFlashModel(
    "You are a world-class biologist. Given a species scientific name, identify the top 3 most commonly confused lookalike species. Provide them exclusively as an array of exact scientific names.",
    150,
  );

  const schema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      similar_species: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description:
          "Exact scientific names of the top 3 closely related but distinct lookalike species.",
      },
    },
    required: ["similar_species"],
  };

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: `Identify lookalikes for: ${scientificName}` }],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: schema as unknown as ResponseSchema,
      },
    });
    const usage = result.response.usageMetadata;
    if (usage) {
      console.log(
        `Token Usage [SimilarSpecies | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      await trackPostHogEvent(user, "SimilarSpeciesLLMCompleted", {
        scientific_name: scientificName,
        llm_model: "gemini-2.5-flash",
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      });
    }
    const extracted = extractJson<{
      similar_species: string[];
      usage?: UsageMetadata;
    }>(result.response.text());
    if (usage) {
      extracted.usage = usage;
    }
    return extracted;
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
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: schema as unknown as ResponseSchema,
      },
    });

    const usage = result.response.usageMetadata;
    if (usage) {
      console.log(
        `Token Usage [GroupTags | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      await trackPostHogEvent(user, "GroupTagsLLMCompleted", {
        scientific_name: scientificName,
        llm_model: "gemini-2.5-flash",
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      });
    }

    const parsed = extractJson<{ group_tags: string[] }>(
      result.response.text(),
    );
    return { group_tags: parsed.group_tags ?? null, usage };
  } catch (e) {
    console.error("fetchGroupTags failed:", e);
    return null;
  }
}
