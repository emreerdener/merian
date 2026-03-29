import { SchemaType, ResponseSchema, UsageMetadata } from "https://esm.sh/@google/generative-ai@0.24.1";
import { User } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createFlashModel, extractJson } from "./gemini.ts";
import { trackPostHogEvent } from "./posthog.ts";

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
  usage?: UsageMetadata;
}

export async function fetchStaticEncyclopedicData(
  user: User,
  scientificName: string,
  locale: string = "en",
): Promise<EncyclopedicData> {
  const textModel = createFlashModel(
    `You are a world-class biologist. Provide encyclopedic identification traits, taxonomy, habitat, toxicity, conservation status, and global distribution for the provided scientific name. Keep descriptions concise. ALL text responses (habitat_description) must be returned in the following ISO language locale: ${locale}.`,
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
    },
    required: ["taxonomy", "iucn_red_list_status", "habitat_description"],
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
        `Token Usage [Encyclopedic | ${scientificName}]: Sent (Prompt): ${usage.promptTokenCount} | Received (Candidates): ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
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
    };
  }
}
