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

export {
  fingerprintBytes,
  fingerprintJson,
} from "../../functions/identify-multimodal/comparison/fingerprint.ts";
import { fingerprintJson } from "../../functions/identify-multimodal/comparison/fingerprint.ts";
export function fingerprintCorpus(value: unknown): Promise<string> {
  return fingerprintJson(parseEvaluationCorpus(value));
}
export function fingerprintEvidence(value: unknown): Promise<string> {
  return fingerprintJson(projectEvaluationEvidence(value));
}
