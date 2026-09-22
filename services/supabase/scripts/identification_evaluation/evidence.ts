import { buildContextText } from "../../functions/_shared/identify/context.ts";
import { parseEvaluationCorpus, parseEvaluationInput } from "./validation.ts";

/** Only this projection is eligible for a later prepared-evidence loader.
 * It contains no reference label, review, split, group or case metadata.
 * Asset descriptors are not provider parts; bytes are not loaded in Slice 1.
 */
export function projectEvaluationEvidence(value: unknown) {
  const input = parseEvaluationInput(value);
  return {
    observationTexts: input.observationTexts,
    captureContext: buildContextText({
      safeGpsLat: null,
      safeGpsLon: null,
      deviceRegion: input.context.deviceRegion,
      currentMonth: input.context.currentMonth,
    }),
    clips: input.clips,
    assets: input.assets,
  };
}

// Canonicalize JSON object keys; array/evidence order remains significant.
function canonical(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  const object = value as Record<string, unknown>;
  return `{${
    Object.keys(object).filter((key) => object[key] !== undefined).sort().map((
      key,
    ) => `${JSON.stringify(key)}:${canonical(object[key])}`).join(",")
  }}`;
}
export async function fingerprintJson(value: unknown): Promise<string> {
  return await fingerprintBytes(new TextEncoder().encode(canonical(value)));
}
export async function fingerprintBytes(value: Uint8Array): Promise<string> {
  const result = await crypto.subtle.digest(
    "SHA-256",
    new Uint8Array(value),
  );
  return Array.from(
    new Uint8Array(result),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}
export function fingerprintCorpus(value: unknown): Promise<string> {
  return fingerprintJson(parseEvaluationCorpus(value));
}
export function fingerprintEvidence(value: unknown): Promise<string> {
  return fingerprintJson(projectEvaluationEvidence(value));
}
