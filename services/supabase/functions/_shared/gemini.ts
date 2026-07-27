import { Content, GoogleGenAI } from "@google/genai";

export const GEMINI_REQUEST_TIMEOUT_MS = 90_000;

// Instantiated once at module scope so warm isolate re-use avoids re-initialization overhead.
export const _genAI = new GoogleGenAI({
  apiKey: Deno.env.get("GEMINI_API_KEY")!,
  httpOptions: {
    timeout: GEMINI_REQUEST_TIMEOUT_MS,
  },
});

/**
 * Creates a thin Flash model wrapper for text-only structured-output calls
 * (encyclopedic data, similar species, group tags). thinkingBudget is set to 0
 * for these calls — they are schema-constrained fact lookups with no visual
 * ambiguity, and the new @google/genai SDK now correctly honours the budget.
 *
 * Returns the native @google/genai GenerateContentResponse directly.
 * Callers access result.text and result.usageMetadata (not result.response.text()).
 */
export function createFlashModel(
  systemInstruction: string,
  maxOutputTokens: number,
  model = "gemini-2.5-flash",
) {
  return {
    generateContent: (params: {
      contents: Content[];
      config?: Record<string, unknown>;
    }) =>
      _genAI.models.generateContent({
        model,
        contents: params.contents,
        config: {
          systemInstruction,
          temperature: 0.1,
          maxOutputTokens,
          thinkingConfig: { thinkingBudget: 0 },
          ...(params.config ?? {}),
        },
      }),
  };
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
  if (start === -1 || end === -1) {
    throw new Error("Malformed Gemini response: no JSON object found");
  }
  return JSON.parse(text.substring(start, end + 1)) as T;
}
