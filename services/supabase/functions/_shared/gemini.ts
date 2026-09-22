import { GoogleGenAI } from "@google/genai";

export const GEMINI_REQUEST_TIMEOUT_MS = 90_000;

let paidGeminiClient: GoogleGenAI | null = null;

function getPaidGeminiClient(): GoogleGenAI {
  if (paidGeminiClient) return paidGeminiClient;

  const apiKey = Deno.env.get("GEMINI_PAID_API_KEY")?.trim();
  if (!apiKey) {
    throw new Error("GEMINI_PAID_API_KEY is not configured.");
  }

  // Instantiated once per warm isolate after the first provider dispatch. Lazy
  // construction keeps unit tests and non-provider routes hermetic while still
  // failing closed before any Gemini request when the paid key is absent.
  paidGeminiClient = new GoogleGenAI({
    apiKey,
    httpOptions: {
      timeout: GEMINI_REQUEST_TIMEOUT_MS,
    },
  });
  return paidGeminiClient;
}

export const _genAI: Pick<GoogleGenAI, "models"> = {
  get models() {
    return getPaidGeminiClient().models;
  },
};

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
