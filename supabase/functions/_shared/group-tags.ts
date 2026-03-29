import {
  SchemaType,
  ResponseSchema,
  UsageMetadata,
} from "https://esm.sh/@google/generative-ai@0.24.1";
import { User } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createFlashModel, extractJson } from "./gemini.ts";
import { trackPostHogEvent } from "./posthog.ts";

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
        `Token Usage [GroupTags | ${scientificName}]: Sent (Prompt): ${usage.promptTokenCount} | Received (Candidates): ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
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
