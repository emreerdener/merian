import { join } from "node:path";
import type {
  AIProviderOutcome,
  MultimodalAIRequest,
} from "../../functions/_shared/ai/contracts.ts";
import type { EvaluationInput } from "./contracts.ts";
import {
  type ExperimentPlan,
  hasAssistantReview,
} from "./experimentContracts.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  atomicJson,
  claimJson,
  exists,
  privateDirectory,
  readJson,
  withRunLock,
} from "./files.ts";
import { normalizeEvaluationDraft } from "./normalization.ts";
import type { NormalizedIdentification } from "../../functions/_shared/identify/normalizeIdentification.ts";
import type { Assignment, AttemptRecord } from "./runContracts.ts";
import {
  CALIBRATION_EXAMPLES,
  calibrationRecord,
  validateCalibration,
} from "./explanationCalibration.ts";
import {
  type AssessmentBinding,
  type FactCard,
  parseFactCards,
  type Ratings,
  ratingsPass,
  RUBRIC,
} from "./explanationContracts.ts";
import { openPrivateReview, type ReviewDisplay } from "./explanationView.ts";
import { requireCondition as check, token } from "./validation.ts";

export async function reviewInputs(root: string, plan: ExperimentPlan) {
  check(plan.review !== undefined);
  const facts = parseFactCards(
    await readJson(join(root, "review", "facts.json"), 128 * 1024),
  );
  if (hasAssistantReview(plan)) {
    check(
      plan.review.method === "assistant_local_v1" &&
        plan.review.calibrationDigest === null,
    );
  } else {
    const calibration = await validateCalibration(
      await readJson(join(root, "review", "calibration.json"), 16384),
      plan.review.reviewerRef,
      plan.mode === "live",
    );
    check(await fingerprintJson(calibration) === plan.review.calibrationDigest);
  }
  check(
    await fingerprintJson(facts) === plan.review.factsDigest &&
      await fingerprintJson(RUBRIC) === plan.review.rubricDigest,
  );
  check(
    facts.cards.length === plan.cases.length &&
      facts.cards.every((c) =>
        plan.cases.some((p) =>
          p.caseId === c.caseId && p.inputDigest === c.inputDigest
        )
      ),
  );
  check(plan.review.cards.length === facts.cards.length);
  for (const card of facts.cards) {
    check(
      await fingerprintJson(card) ===
        plan.review.cards.find((c) => c.caseId === card.caseId)?.digest,
    );
  }
  return facts;
}
export async function assessmentBinding(
  plan: ExperimentPlan,
  runIndex: number,
  runDigest: string,
  a: Assignment,
  record: AttemptRecord,
  factCardDigest: string,
): Promise<AssessmentBinding> {
  const r = plan.runs[runIndex];
  check(plan.review);
  return {
    planDigest: await fingerprintJson(plan),
    runDigest,
    key: a.key,
    requestDigest: a.requestDigest,
    profileId: r.profileId,
    profileDigest: r.profileDigest,
    inputDigest: a.inputDigest,
    factCardDigest,
    resultDigest: await fingerprintJson(record),
    calibrationDigest: plan.review.calibrationDigest,
    rubricDigest: plan.review.rubricDigest,
    reviewerRef: plan.review.reviewerRef,
  };
}
/** Projection for the private UI only. It must never reach atomicJson or logs. */
export function explanationDisplay(
  outcome: AIProviderOutcome,
  input: EvaluationInput,
  assignment: Assignment,
  request: MultimodalAIRequest,
  card: FactCard,
): ReviewDisplay | null {
  if (outcome.kind !== "draft") return null;
  const normalized = normalizeEvaluationDraft(
    outcome.draft,
    input,
    assignment.profile,
  );
  return normalizedExplanationDisplay(normalized, request, card);
}

/** Shared transient view; the caller has already normalized under its exact profile. */
export function normalizedExplanationDisplay(
  normalized: NormalizedIdentification,
  request: MultimodalAIRequest,
  card: FactCard,
): ReviewDisplay | null {
  const v = normalized.identification;
  const strings = (x: unknown): string[] =>
    typeof x === "string"
      ? [x]
      : Array.isArray(x) && x.every((s) => typeof s === "string")
      ? x
      : [];
  const explanation = [
    ...strings(v.ai_reasoning),
    ...strings(v.extracted_visual_traits),
    ...strings(v.invasive_rationale),
    ...(normalized.clientCandidates ?? []).flatMap((c) =>
      strings(c.distinguishing_feature).map((s) =>
        `Alternative ${c.scientific_name}: ${s}`
      )
    ),
  ];
  if (
    !strings(v.ai_reasoning).length ||
    explanation.some((s) => s.length > 2000) || explanation.length > 20
  ) return null;
  return {
    title: "Review this identification explanation",
    observation: request.evidence.filter((e) => e.kind === "text").map((e) =>
      e.text
    ),
    images: request.evidence.filter((e) => e.kind === "image").map((e) => ({
      mimeType: e.mimeType,
      data: e.data,
    })),
    facts: [
      ...card.observed,
      ...card.missing.map((s) => `Missing: ${s}`),
      ...card.acceptableReasons.map((s) => `Acceptable reason: ${s}`),
      `Rank limit: ${card.rankLimit}`,
      `Requirements: ${card.requirements.join(", ")}`,
    ],
    decision: [
      v.is_biological_subject ? "Biological subject" : "Non-biological subject",
      ...strings(v.scientific_name),
      ...strings(v.common_name),
    ],
    explanation,
  };
}
export async function reviewExplanation(
  display: ReviewDisplay | null,
  timeoutMs: number,
  assistant = false,
) {
  if (!display) return null;
  return await openPrivateReview(
    assistant ? { ...display, reviewerKind: "assistant" } : display,
    timeoutMs,
  );
}
export async function calibrateReviewer(root: string, reviewerRef: string) {
  token(reviewerRef);
  check((await Deno.permissions.query({ name: "env" })).state === "denied");
  check((await Deno.permissions.query({ name: "net" })).state !== "granted");
  for (
    const host of [
      "api.openai.com:443",
      "generativelanguage.googleapis.com:443",
    ]
  ) {
    check(
      (await Deno.permissions.query({ name: "net", host })).state !== "granted",
    );
  }
  const directory = await privateDirectory(join(root, "review"));
  await withRunLock(directory, async () => {
    check(
      !await exists(join(root, "experiment")) &&
        !await exists(join(directory, "calibration.json")),
    );
    const ratings: Ratings[] = [];
    for (const [index, c] of CALIBRATION_EXAMPLES.entries()) {
      const result = await openPrivateReview({
        title: `Practice review ${index + 1} of 8`,
        observation: [c.observation],
        images: [],
        facts: [
          "Use the Observation text above as the reference for this invented practice example. Assume those facts are true and compare the Explanation with them. There is no separate photo or source to look up.",
        ],
        decision: [],
        explanation: [c.explanation],
      }, 600000);
      check(result !== null);
      ratings.push(result);
    }
    const record = await calibrationRecord(reviewerRef, ratings);
    if (!record.passed) {
      await atomicJson(join(directory, "calibration-feedback.json"), {
        version: "explanation_calibration_feedback_v1",
        ratings,
        expected: CALIBRATION_EXAMPLES.map((c) => c.expected),
      });
      throw new Error("explanation_calibration_failed");
    }
    await claimJson(join(directory, "calibration.json"), record);
  });
}
export { ratingsPass };
