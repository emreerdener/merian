import { SchemaType, ResponseSchema } from "https://esm.sh/@google/generative-ai@0.24.1";
import { User } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createFlashModel, extractJson } from "./gemini.ts";
import { trackPostHogEvent } from "./posthog.ts";

export async function fetchDiagnosticComparison(
  user: User,
  scientificName: string,
) {
  const model = createFlashModel(
    "You are a world-class biologist. Given a species scientific name, return a brief diagnostic comparison explaining the primary identification rationale, the most commonly confused lookalike species, and the key morphological or behavioural features that differentiate them.",
    400,
  );

  const schema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      primary_match_rationale: { type: SchemaType.STRING },
      confusing_lookalike_name: { type: SchemaType.STRING },
      key_differentiators: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description: "2–4 concise differentiating features vs. the lookalike.",
      },
    },
    required: [
      "primary_match_rationale",
      "confusing_lookalike_name",
      "key_differentiators",
    ],
  };

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: `Diagnostic comparison for: ${scientificName}` }],
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
        `Token Usage [Diagnostic | ${scientificName}]: Sent (Prompt): ${usage.promptTokenCount} | Received (Candidates): ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      await trackPostHogEvent(user, "DiagnosticLLMCompleted", {
        scientific_name: scientificName,
        llm_model: "gemini-2.5-flash",
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      });
    }
    return extractJson<{
      primary_match_rationale: string;
      confusing_lookalike_name: string;
      key_differentiators: string[];
    }>(result.response.text());
  } catch (e) {
    console.error("fetchDiagnosticComparison failed:", e);
    return null;
  }
}
