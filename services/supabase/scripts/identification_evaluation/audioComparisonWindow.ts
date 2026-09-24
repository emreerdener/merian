import {
  AUDIO_COMPARISON_EVENT_VERSION,
  parseAudioComparisonEvent,
} from "./audioComparisonObservation.ts";
import {
  AUDIO_COMPARISON_PLAN,
  AUDIO_COMPARISON_PLAN_SHA256,
} from "../../functions/identify-multimodal/comparison/plan.ts";
import {
  admitComparisonWindowEvidence,
  parseComparisonWindowExpectation,
} from "./comparisonWindow.ts";
export type { ComparisonWindowExpectation as AudioComparisonExpectation } from "./comparisonWindow.ts";
export function parseAudioComparisonExpectation(value: unknown) {
  return parseComparisonWindowExpectation(value, 12);
}
/** Historical DSP interpretation and artifact version remain fixed. */
export function admitAudioComparisonWindow(
  rows: unknown[],
  expectedValue: unknown,
) {
  const expected = parseAudioComparisonExpectation(expectedValue);
  const { outcome, ...evidence } = admitComparisonWindowEvidence(
    rows,
    expected,
    {
      version: AUDIO_COMPARISON_EVENT_VERSION,
      parse: parseAudioComparisonEvent,
    },
  );
  return {
    version: "identification_audio_comparison_observation_v1",
    planSha256: AUDIO_COMPARISON_PLAN_SHA256,
    assignment: AUDIO_COMPARISON_PLAN.assignments[expected.slot - 1],
    ...evidence,
    nativeOutcome: {
      confidenceScore: outcome.confidenceScore,
      isBiological: outcome.isBiological,
      persistence: outcome.persistence,
    },
  };
}
