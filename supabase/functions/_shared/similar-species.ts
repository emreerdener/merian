import { SchemaType, ResponseSchema } from "https://esm.sh/@google/generative-ai@0.24.1";
import { User } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createFlashModel, extractJson } from "./gemini.ts";
import { trackPostHogEvent } from "./posthog.ts";

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
        description: "Exact scientific names of the top 3 closely related but distinct lookalike species.",
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
    return extractJson<{
      similar_species: string[];
    }>(result.response.text());
  } catch (e) {
    console.error("fetchSimilarSpecies failed:", e);
    return null;
  }
}
