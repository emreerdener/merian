import {
  GoogleGenerativeAI,
  GenerativeModel,
} from "https://esm.sh/@google/generative-ai@0.24.1";

// Instantiated once at module scope so warm isolate re-use avoids re-initialization overhead.
export const _genAI = new GoogleGenerativeAI(
  Deno.env.get("GEMINI_API_KEY")!,
);

/**
 * Creates a gemini-2.5-flash model with the given system instruction.
 * Use for all background/enrichment AI calls. The vision model in `identify`
 * uses `_genAI.getGenerativeModel` directly so it can select flash vs. pro
 * based on the user's subscription tier.
 */
export function createFlashModel(
  systemInstruction: string,
  maxOutputTokens: number,
): GenerativeModel {
  return _genAI.getGenerativeModel({
    model: "gemini-2.5-flash",
    systemInstruction,
    generationConfig: { temperature: 0.1, maxOutputTokens },
  });
}

/**
 * Extracts the outermost JSON object from a Gemini response string.
 *
 * Gemini occasionally wraps JSON in markdown fences or preamble text even
 * with `responseMimeType: "application/json"`, so we extract the outermost
 * object explicitly rather than calling `JSON.parse` directly.
 *
 * @throws {Error} if no valid JSON object boundaries are found.
 */
export function extractJson<T = unknown>(text: string): T {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1) throw new Error("Malformed Gemini response: no JSON object found");
  return JSON.parse(text.substring(start, end + 1)) as T;
}
