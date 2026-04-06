import { GoogleGenAI, Content } from "https://esm.sh/@google/genai@1.0.0";

// Instantiated once at module scope so warm isolate re-use avoids re-initialization overhead.
export const _genAI = new GoogleGenAI({ apiKey: Deno.env.get("GEMINI_API_KEY")! });

/**
 * Creates a thin Flash model wrapper for text-only structured-output calls
 * (encyclopedic data, similar species, group tags). thinkingBudget is set to 0
 * for these calls — they are schema-constrained fact lookups with no visual
 * ambiguity, and the new @google/genai SDK now correctly honours the budget.
 *
 * The returned wrapper preserves the legacy .generateContent() call signature
 * used by biology.ts callers (result.response.text(), result.response.usageMetadata)
 * so those files require no API-surface changes.
 */
export function createFlashModel(systemInstruction: string, maxOutputTokens: number) {
  return {
    generateContent: async (params: {
      contents: Content[];
      generationConfig?: Record<string, unknown>;
    }) => {
      const result = await _genAI.models.generateContent({
        model: "gemini-2.5-flash",
        contents: params.contents,
        config: {
          systemInstruction,
          temperature: 0.1,
          maxOutputTokens,
          thinkingConfig: { thinkingBudget: 0 },
          ...(params.generationConfig ?? {}),
        },
      });
      // Normalize to the old @google/generative-ai response shape that biology.ts callers
      // expect: result.response.text() (method) and result.response.usageMetadata (object).
      return {
        response: {
          text: () => result.text ?? "",
          usageMetadata: result.usageMetadata,
          candidates: result.candidates,
        },
      };
    },
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
  if (start === -1 || end === -1) throw new Error("Malformed Gemini response: no JSON object found");
  return JSON.parse(text.substring(start, end + 1)) as T;
}
