import {
  type NormalizedIdentification,
  normalizeIdentification,
} from "../../functions/_shared/identify/normalizeIdentification.ts";
import type { Profile } from "./contracts.ts";
import { parseEvaluationInput } from "./validation.ts";

/**
 * In-memory bridge for prepared evaluation inputs. The loader must first prove
 * every declared asset was included in the actual request; it may not silently
 * drop failed media. No reference label, taxonomy lookup or provider call here.
 * This result contains model prose/diagnostics and is NOT a durable Prediction.
 */
export function normalizeEvaluationDraft(
  draft: unknown,
  inputValue: unknown,
  profile: Profile,
): NormalizedIdentification {
  if (profile !== "gemini_flash_free" && profile !== "gemini_pro") {
    throw new Error("evaluation_profile_invalid");
  }
  const input = parseEvaluationInput(inputValue);
  return normalizeIdentification(draft, {
    hasVisualEvidence: input.assets.some((asset) =>
      asset.kind === "image" || asset.kind === "video_frame"
    ),
    hasAudioEvidence: input.assets.some((asset) =>
      asset.kind === "audio" || asset.kind === "video_audio"
    ),
    // Current corpus context is deviceRegion/month only. Production's invasive
    // rule needs GPS or semanticLocation; a device region is not either one.
    hasInvasiveLocationContext: false,
    inferenceTier: profile === "gemini_pro" ? "pro" : "flash",
  });
}
