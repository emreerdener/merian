import { enterGeminiTransport } from "./ai/geminiTransport.ts";
import { type GenerateContentParameters, GoogleGenAI } from "@google/genai";

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

/** Direct SDK callers share the same bounded normalization and receipt path. */
export async function generateGeminiContent(
  parameters: GenerateContentParameters,
  hooks?: import("./ai/geminiTransport.ts").GeminiTransportHooks,
  maximumBytes = 32 * 1024,
) {
  const {
    normalizeGeminiEnvelope,
    geminiResponseReceipt,
    GeminiResponseRejected,
  } = await import("./ai/geminiEnvelope.ts");
  if (!hooks) throw new Error("gemini_transport_authority_required");
  const models = _genAI.models;
  await enterGeminiTransport(hooks, parameters.model);
  const response = await models.generateContent(parameters);
  const normalized = normalizeGeminiEnvelope(
    response,
    parameters.model,
    maximumBytes,
  );
  const receipt = geminiResponseReceipt(normalized);
  await hooks?.recordResponse(receipt);
  if (normalized.failure || !normalized.text) {
    await hooks.recordApplicationOutcome?.("error");
    throw new GeminiResponseRejected(receipt);
  }
  return {
    text: normalized.text,
    usageMetadata: response.usageMetadata,
    modelVersion: normalized.returnedModel,
  };
}
