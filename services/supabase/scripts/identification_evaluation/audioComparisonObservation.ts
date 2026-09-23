import {
  AUDIO_COMPARISON_PLAN,
  AUDIO_COMPARISON_PLAN_SHA256,
} from "../../functions/identify-multimodal/comparison/plan.ts";
import { fields, integer, requireCondition as check } from "./validation.ts";

export const AUDIO_COMPARISON_MARKER = "[⏱ BENCH] Audio comparison ";
export const AUDIO_COMPARISON_EVENT_VERSION =
  "identification_audio_comparison_v1";
export type NumericAppEvent = Record<string, string | number | boolean>;

/** Native proof is an authenticated-header claim checked against the frozen
 * table. These compact records retain neither source media nor result prose. */
export function parseAudioComparisonEvent(value: unknown): NumericAppEvent {
  const event = (value as { event?: unknown } | null)?.event;
  check(
    typeof event === "string" &&
      ["receipt", "finalized", "rendered"].includes(event),
  );
  const v = fields(value, [
    "version",
    "event",
    "planSha256",
    "slot",
    "measurementSha256",
    ...(event === "finalized"
      ? ["confidenceScore", "isBiological", "persistence"]
      : []),
  ]);
  check(v.version === AUDIO_COMPARISON_EVENT_VERSION);
  check(v.planSha256 === AUDIO_COMPARISON_PLAN_SHA256);
  integer(v.slot, 1, AUDIO_COMPARISON_PLAN.assignments.length);
  check(
    typeof v.measurementSha256 === "string" &&
      v.measurementSha256.length === 64 &&
      /^[0-9a-f]{64}$/.test(v.measurementSha256),
  );
  if (event === "finalized") {
    check(
      typeof v.confidenceScore === "number" &&
        Number.isFinite(v.confidenceScore) && v.confidenceScore >= 0 &&
        v.confidenceScore <= 1,
    );
    check(typeof v.isBiological === "boolean");
    check(
      typeof v.persistence === "string" &&
        ["saved", "completed_without_record"].includes(v.persistence),
    );
  }
  return structuredClone(v) as NumericAppEvent;
}
