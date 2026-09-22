import type { GenerateContentParameters } from "@google/genai";

type ResponseSchema = NonNullable<
  NonNullable<GenerateContentParameters["config"]>["responseSchema"]
>;

// Shared by the deployed reply paths and the synthetic live-answer check.
export function buildFieldChatReplyRequest(
  systemInstruction: string,
  userPrompt: string,
  model: string,
): GenerateContentParameters {
  return {
    model,
    contents: [{ role: "user", parts: [{ text: userPrompt }] }],
    config: {
      systemInstruction,
      temperature: 0.2,
      maxOutputTokens: 700,
      responseMimeType: "application/json",
      responseSchema: {
        type: "OBJECT",
        properties: {
          answer: { type: "STRING" },
          is_refusal: { type: "BOOLEAN" },
          refusal_reason: { type: "STRING", nullable: true },
        },
        required: ["answer", "is_refusal", "refusal_reason"],
      } as ResponseSchema,
      thinkingConfig: { thinkingBudget: 0 },
    },
  };
}

export function extractFieldChatReplyJson<T>(text: string): T {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1) {
    throw new Error("Malformed Gemini response: no JSON object found");
  }
  return JSON.parse(text.substring(start, end + 1)) as T;
}
