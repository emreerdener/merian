import type { GenerateContentParameters } from "@google/genai";
import {
  candidateGeneration,
  GEMINI_SUPPORT_MODEL,
} from "../ai/geminiProfiles.ts";

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
      ...(model === GEMINI_SUPPORT_MODEL ? candidateGeneration("field_chat") : {
        temperature: 0.2,
        maxOutputTokens: 700,
        thinkingConfig: { thinkingBudget: 0 },
      }),
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

/** Close application JSON independently from provider metadata and token limits. */
export function fieldChatResponseObject(
  value: unknown,
  keys: readonly string[],
) {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).length !== keys.length ||
    keys.some((key) => !Object.hasOwn(value, key))
  ) {
    throw new Error("field_chat_response_invalid");
  }
  return value as Record<string, unknown>;
}
export function parseFieldChatReply(text: string) {
  const row = fieldChatResponseObject(extractFieldChatReplyJson(text), [
    "answer",
    "is_refusal",
    "refusal_reason",
  ]);
  if (
    typeof row.answer !== "string" || typeof row.is_refusal !== "boolean" ||
    (row.refusal_reason !== null && typeof row.refusal_reason !== "string")
  ) {
    throw new Error("field_chat_response_invalid");
  }
  const answer = row.answer.trim();
  const reason = typeof row.refusal_reason === "string"
    ? row.refusal_reason.trim()
    : null;
  if (
    !answer || [...answer].length > 4000 ||
    (reason !== null &&
      (!reason || [...reason].length > 100 || !row.is_refusal))
  ) {
    throw new Error("field_chat_response_invalid");
  }
  return { answer, is_refusal: row.is_refusal, refusal_reason: reason };
}
