import { assertEquals, assertRejects } from "@std/assert";
import {
  OPENAI_NULL_FIELDS_PROFILE,
  OPENAI_NULL_FIELDS_PROMPT_DIGEST,
  openAINullFieldsInstructions,
} from "../functions/_shared/ai/openaiNullFields.ts";
import {
  buildOpenAIRequestParameters,
  openAIEvaluationSnapshot,
} from "../functions/_shared/ai/openaiRequest.ts";
import { openAITextFixture } from "../functions/_shared/ai/testing/openaiFixtures.ts";
import { fingerprintJson } from "./identification_evaluation/evidence.ts";
import {
  reusableAssignmentFor,
  reusableProfile,
} from "./identification_evaluation/reusableProfiles.ts";
import { syntheticCorpus } from "./identification_evaluation/fixtures.ts";
import { screenNullFieldsCandidate } from "./identification_evaluation/nullFieldsReport.ts";
import type { CandidateComparison } from "./identification_evaluation/candidateReport.ts";
import { CALIBRATION_EXAMPLES } from "./identification_evaluation/explanationCalibration.ts";
import { unavailableRatings } from "./identification_evaluation/explanationContracts.ts";

Deno.test("null-field implementation exactly matches the frozen four-edit proposal and preserves baseline profile digests", async () => {
  const manifest = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../../../docs/rfcs/identification-evaluation-evidence/2026-09-27-openai-prompt-review/prompt-edits.json",
        import.meta.url,
      ),
    ),
  ) as {
    sourceSha: string;
    replacements: { before: string; after: string }[];
    baselinePromptDigest: string;
    schemaDigest: string;
  };
  assertEquals(manifest.sourceSha, "2bbacb8c895903052d1d60be9eac1fa69deba176");
  assertEquals(manifest.replacements.length, 4);
  const request = {
    ...openAITextFixture(),
    evidence: [
      {
        kind: "image",
        order: 0,
        inputIndex: 0,
        lineage: null,
        mimeType: "image/png",
        data: "AQID",
      } as const,
    ],
  };
  const baseline = buildOpenAIRequestParameters(
    request,
    openAIEvaluationSnapshot(request),
  );
  const proposed = manifest.replacements.reduce((s, edit) => {
    assertEquals(s.split(edit.before).length, 2);
    return s.replace(edit.before, edit.after);
  }, baseline.instructions);
  assertEquals(openAINullFieldsInstructions(baseline.instructions), proposed);
  assertEquals(
    await fingerprintJson(proposed),
    OPENAI_NULL_FIELDS_PROMPT_DIGEST,
  );
  assertEquals(
    (await reusableProfile("gemini_photo_text_v1")).digest,
    "0de814f2b9534e066175bc55b0d2cb26463bb3c3fc7dd0a3d46928596a8c6dc9",
  );
  assertEquals(
    (await reusableProfile("openai_photo_text_v1")).digest,
    "b44c88586f48bde74d3b6f316b379160777d991860529c2089e4f64413939d01",
  );
  const candidate = await reusableProfile(OPENAI_NULL_FIELDS_PROFILE);
  assertEquals(candidate.definition.supportedInputs, ["photos"]);
  assertEquals(candidate.definition.bindings.length, 1);
  assertEquals(
    candidate.definition.bindings[0].schemaDigest,
    manifest.schemaDigest,
  );
  // Text-only cannot inherit the new visual assignment through a reusable profile.
  const text =
    syntheticCorpus().cases.find((c) => c.input.inputGroup === "description")!
      .input;
  await assertRejects(
    () =>
      reusableAssignmentFor(
        text,
        openAITextFixture(),
        OPENAI_NULL_FIELDS_PROFILE,
        1,
        null,
      ),
    Error,
    "openai_input_unsupported",
  );
});

Deno.test("six-photo null-field screen checks quality without a speed threshold or cache claim", () => {
  const good = {
    subject: "agreement",
    identity: "agreement",
    falseBiological: false,
    unsupportedBiological: false,
    unsupportedSpecificity: false,
  };
  const comparison: CandidateComparison = {
    slices: [{
      inputGroup: "all_cases",
      baseline: { scheduled: 6 },
      candidate: { scheduled: 6 },
      observedLatencyImprovementPercent: -30,
      observedCostImprovementPercent: null,
      paired: Array.from(
        { length: 6 },
        () => ({ left: { ...good }, right: { ...good } }),
      ),
    }],
  };
  const assessments = Array.from(
    { length: 12 },
    () => ({ ratings: structuredClone(CALIBRATION_EXAMPLES[0].expected) }),
  );
  const state = { live: true, complete: true };
  assertEquals(
    screenNullFieldsCandidate(comparison, assessments, state),
    "no_observed_regression_in_six_photo_screen",
  );
  for (const identity of ["not_applicable", "valid_abstention"]) {
    const valid = structuredClone(comparison);
    valid.slices[0].paired[0] = {
      left: { ...good, identity },
      right: { ...good, identity },
    };
    assertEquals(
      screenNullFieldsCandidate(valid, assessments, state),
      "no_observed_regression_in_six_photo_screen",
    );
  }
  for (
    const fault of [
      { identity: "unsupported_specificity" },
      { identity: "disagreement" },
      { subject: "disagreement" },
      { falseBiological: true },
      { unsupportedBiological: true },
    ]
  ) {
    const bad = structuredClone(comparison);
    Object.assign(bad.slices[0].paired[0].right, fault);
    assertEquals(
      screenNullFieldsCandidate(bad, assessments, state),
      "retain_baseline_quality_regression",
    );
  }
  for (
    const identity of [
      "unresolved",
      "ambiguous",
      "unmapped",
      "unverified",
      "no_result",
    ]
  ) {
    const bad = structuredClone(comparison);
    bad.slices[0].paired[0].right.identity = identity;
    assertEquals(
      screenNullFieldsCandidate(bad, assessments, state),
      "inconclusive",
    );
  }
  assertEquals(
    screenNullFieldsCandidate(comparison, assessments.slice(1), state),
    "inconclusive",
  );
  assertEquals(
    screenNullFieldsCandidate(comparison, [
      { ratings: unavailableRatings() },
      ...assessments.slice(1),
    ], state),
    "inconclusive",
  );
  assertEquals(
    screenNullFieldsCandidate(comparison, assessments, {
      live: true,
      complete: false,
    }),
    "inconclusive",
  );
  assertEquals(
    screenNullFieldsCandidate(comparison, [], { live: false, complete: false }),
    "synthetic_mechanics_only",
  );
});
