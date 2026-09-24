// Synthetic observer metadata; never submits an identification.
import { audioComparisonObservationFixture } from "./audioComparisonFixture.ts";
import { AUDIO_PROMPT_COMPARISON_PLAN_SHA256 } from "../../../functions/identify-multimodal/comparison/promptPlan.ts";
import { AUDIO_PROMPT_COMPARISON_EVENT_VERSION } from "../audioPromptComparisonObservation.ts";

export function audioPromptComparisonObservationFixture(slot = 2) {
  const f = audioComparisonObservationFixture();
  f.expected.slot = slot;
  for (const row of f.rows) {
    const event = row.measurement as Record<string, unknown> | undefined;
    if (event?.version !== "identification_audio_comparison_v1") continue;
    event.version = AUDIO_PROMPT_COMPARISON_EVENT_VERSION;
    event.planSha256 = AUDIO_PROMPT_COMPARISON_PLAN_SHA256;
    event.slot = slot;
    if (event.event === "finalized") {
      event.subjectState = "unidentified_non_human";
    }
  }
  return { ...f, outcome: f.rows[7].measurement as Record<string, unknown> };
}
