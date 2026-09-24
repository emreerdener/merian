import {
  AUDIO_PROMPT_COMPARISON_PLAN,
  AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
} from "../../functions/identify-multimodal/comparison/promptPlan.ts";
import {
  AUDIO_PROMPT_COMPARISON_EVENT_VERSION,
  parseAudioPromptComparisonEvent,
} from "./audioPromptComparisonObservation.ts";
import {
  admitComparisonWindowEvidence,
  parseComparisonWindowExpectation,
} from "./comparisonWindow.ts";
import { audioUncertaintyDesign } from "./audioPromptComparison.ts";
import { fingerprintBytes } from "./evidence.ts";
import { requireCondition as check } from "./validation.ts";

export async function admitAudioPromptComparisonWindow(
  rows: unknown[],
  expectedValue: unknown,
) {
  const expected = parseComparisonWindowExpectation(expectedValue, 36);
  const { outcome, ...evidence } = admitComparisonWindowEvidence(
    rows,
    expected,
    {
      version: AUDIO_PROMPT_COMPARISON_EVENT_VERSION,
      parse: parseAudioPromptComparisonEvent,
      exactSeconds: 120,
    },
  );
  const assignment =
    AUDIO_PROMPT_COMPARISON_PLAN.assignments[expected.slot - 1];
  const design = await audioUncertaintyDesign();
  const reference = design.cases.find((c) => c.caseId === assignment.caseId)
    ?.reference;
  check(reference);
  let provisionalSpeciesAgreement = "not_applicable";
  if (
    outcome.subjectState === "identified_non_human" &&
    reference.scientificName !== null
  ) {
    const name = reference.scientificName.trim().split(/\s+/).join(" ")
      .toLowerCase();
    const expectedHash = await fingerprintBytes(new TextEncoder().encode(name));
    provisionalSpeciesAgreement = outcome.scientificNameSha256 === expectedHash
      ? "agreement"
      : "mismatch";
  }
  return {
    version: "identification_audio_prompt_comparison_observation_v1",
    planSha256: AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
    assignment,
    ...evidence,
    nativeOutcome: {
      confidenceScore: outcome.confidenceScore,
      isBiological: outcome.isBiological,
      persistence: outcome.persistence,
      subjectState: outcome.subjectState,
      ...(outcome.scientificNameSha256
        ? { scientificNameSha256: outcome.scientificNameSha256 }
        : {}),
    },
    provisionalSpeciesAgreement,
    formalQualificationEligible: false,
  };
}
