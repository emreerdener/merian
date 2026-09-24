import { AUDIO_PROMPT_COMPARISON_PLAN_SHA256 } from "../../functions/identify-multimodal/comparison/promptPlan.ts";
import { fields, integer, requireCondition as check } from "./validation.ts";
import { hash } from "./runContracts.ts";
import type { NumericAppEvent } from "./audioComparisonObservation.ts";

export const AUDIO_PROMPT_COMPARISON_MARKER =
  "[⏱ BENCH] Audio prompt comparison ";
export const AUDIO_PROMPT_COMPARISON_EVENT_VERSION =
  "identification_audio_prompt_comparison_v1";

/** Source names and raw result prose never enter logs; a named animal retains
 * only the digest of its whitespace-normalized, lowercased scientific name. */
export function parseAudioPromptComparisonEvent(
  value: unknown,
): NumericAppEvent {
  const raw = value as { event?: unknown; subjectState?: unknown } | null;
  const event = raw?.event;
  check(
    typeof event === "string" &&
      ["receipt", "finalized", "rendered"].includes(event),
  );
  const named = event === "finalized" &&
    raw?.subjectState === "identified_non_human";
  const v = fields(value, [
    "version",
    "event",
    "planSha256",
    "slot",
    "measurementSha256",
    ...(event === "finalized"
      ? ["confidenceScore", "isBiological", "persistence", "subjectState"]
      : []),
    ...(named ? ["scientificNameSha256"] : []),
  ]);
  check(
    v.version === AUDIO_PROMPT_COMPARISON_EVENT_VERSION &&
      v.planSha256 === AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
  );
  integer(v.slot, 1, 36);
  hash(v.measurementSha256);
  if (event === "finalized") {
    check(
      typeof v.confidenceScore === "number" &&
        Number.isFinite(v.confidenceScore) &&
        v.confidenceScore >= 0 && v.confidenceScore <= 1,
    );
    check(typeof v.isBiological === "boolean");
    check(
      typeof v.subjectState === "string" && [
        "identified_non_human",
        "unidentified_non_human",
        "human",
        "non_biological",
      ].includes(v.subjectState),
    );
    check(v.isBiological === (v.subjectState !== "non_biological"));
    check(
      typeof v.persistence === "string" &&
        ["saved", "completed_without_record"].includes(v.persistence),
    );
    if (named) hash(v.scientificNameSha256);
  }
  return structuredClone(v) as NumericAppEvent;
}
