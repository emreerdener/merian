/** Distinct amendment contract; never changes the original execution schema. */
import {
  AUDIO_PROMPT_COMPARISON_PLAN as PLAN,
  AUDIO_PROMPT_COMPARISON_PLAN_SHA256 as PLAN_SHA,
} from "../../functions/identify-multimodal/comparison/promptPlan.ts";
import { IDENTIFICATION_BUNDLE_SHA256 } from "../../functions/identify-multimodal/deploymentIdentity.ts";
import { PROMPT_COMPARISON_PROJECT } from "../control_audio_prompt_comparison.ts";
import {
  executionInstant,
  promptPrivatePreflight,
} from "./audioPromptExecution.ts";
import type { OriginalPromptBinding } from "./audioPromptExecutionEvidence.ts";
import { parseComparisonWindowExpectation } from "./comparisonWindow.ts";
import { hash, parsePricing, type SourceIdentity } from "./runContracts.ts";
import {
  array,
  fields,
  integer,
  requireCondition as check,
} from "./validation.ts";

const revision = (v: unknown) => {
  check(typeof v === "string" && /^[a-f0-9]{40}$/.test(v));
  return v;
};

export function parseOriginalPromptBinding(
  value: unknown,
): OriginalPromptBinding {
  const v = fields(value, [
    "manifestSha256",
    "evidenceSha256",
    "completedThrough",
    "lastCompletedAt",
    "lastCleanupAt",
    "expiredAt",
    "app",
    "backendBundleSha256",
    "deployedSha",
    "pricing",
  ]);
  hash(v.manifestSha256);
  hash(v.evidenceSha256);
  integer(v.completedThrough, 1, 35);
  check(v.completedThrough % 12 !== 0);
  check(
    executionInstant(v.lastCompletedAt) <= executionInstant(v.lastCleanupAt),
  );
  check(executionInstant(v.lastCompletedAt) < executionInstant(v.expiredAt));
  check(executionInstant(v.lastCleanupAt) >= executionInstant(v.expiredAt));
  const expected = parseComparisonWindowExpectation({
    slot: 1,
    app: v.app,
    backendBundleSha256: v.backendBundleSha256,
  }, 36);
  check(
    expected.app.sourceState === "clean" &&
      expected.backendBundleSha256 === IDENTIFICATION_BUNDLE_SHA256,
  );
  revision(expected.app.sourceRevision);
  revision(v.deployedSha);
  parsePricing(v.pricing);
  return structuredClone(v) as unknown as OriginalPromptBinding;
}

export function promptContinuationManifest(
  reviewValue: unknown,
  originalValue: unknown,
  toolingValue: unknown,
  now: number,
) {
  const original = parseOriginalPromptBinding(originalValue);
  const tooling = fields(toolingValue, ["commit", "dirty", "digest", "sdk"]);
  revision(tooling.commit);
  hash(tooling.digest);
  check(tooling.dirty === false && tooling.sdk === "npm:@google/genai@2.23.0");
  check(reviewValue !== null && typeof reviewValue === "object");
  const reviewVersion = "version" in reviewValue ? reviewValue.version : null;
  check(
    reviewVersion === "audio_prompt_continuation_review_v1" ||
      reviewVersion === "audio_prompt_continuation_review_v2",
  );
  const review = fields(reviewValue, [
    "version",
    "reviewedAt",
    "sourceSha",
    "originalEvidenceSha256",
    "firstSlot",
    "windows",
    "privatePreflight",
    "noUnrecordedAttempts",
    "remainingNeverSubmitted",
    "pauseBetweenCompletedSlots",
    "analysisPolicy",
    ...(reviewVersion === "audio_prompt_continuation_review_v2"
      ? ["deployedSha"]
      : []),
  ]);
  const deploymentBinding =
    reviewVersion === "audio_prompt_continuation_review_v2"
      ? { deployedSha: revision(review.deployedSha) }
      : {};
  const reviewedAt = executionInstant(review.reviewedAt);
  check(
    Number.isFinite(now) && reviewedAt <= now &&
      reviewedAt >= executionInstant(original.lastCleanupAt),
  );
  check(reviewedAt >= executionInstant(original.expiredAt));
  check(
    review.sourceSha === tooling.commit &&
      review.originalEvidenceSha256 === original.evidenceSha256,
  );
  check(review.firstSlot === original.completedThrough + 1);
  for (
    const key of [
      "noUnrecordedAttempts",
      "remainingNeverSubmitted",
      "pauseBetweenCompletedSlots",
    ]
  ) check(review[key] === true);
  check(
    review.analysisPolicy ===
      "original_screening_rules_with_disclosed_interruption",
  );
  const privatePreflight = promptPrivatePreflight(
    review.privatePreflight,
    reviewedAt,
    reviewedAt - 300_000,
  );
  promptPrivatePreflight(privatePreflight, now, now - 300_000);
  const firstBlock = Math.ceil((original.completedThrough + 1) / 12);
  let previousStart = reviewedAt, previousEnd = reviewedAt;
  const pricedAt = executionInstant(original.pricing.retrievedAt);
  const windows = array(review.windows, 4 - firstBlock, 4 - firstBlock).map(
    (value, i) => {
      const w = fields(value, ["block", "startsAt", "expiresAt"]);
      check(w.block === firstBlock + i);
      const start = executionInstant(w.startsAt),
        end = executionInstant(w.expiresAt);
      check(
        start >= previousStart && end > previousEnd && end > start &&
          end - start <= 7_200_000,
      );
      check(
        start >= Date.parse(PLAN.startsNotBefore) &&
          end <= Date.parse(PLAN.expiresNotAfter),
      );
      check(end - pricedAt <= 7 * 86_400_000);
      previousStart = start;
      previousEnd = end;
      return {
        block: firstBlock + i,
        startsAt: w.startsAt as string,
        expiresAt: w.expiresAt as string,
      };
    },
  );
  check(now + 151_000 < executionInstant(windows[0].expiresAt));
  return {
    version: "audio_prompt_continuation_manifest_v1" as const,
    preparedAt: new Date(now).toISOString(),
    planSha256: PLAN_SHA,
    original,
    tooling: structuredClone(tooling) as unknown as SourceIdentity,
    review: {
      ...review,
      version: reviewVersion,
      ...deploymentBinding,
      privatePreflight,
      windows,
      analysisPolicy:
        "original_screening_rules_with_disclosed_interruption" as const,
    },
    firstSlot: original.completedThrough + 1,
    remainingSlots: Array.from(
      { length: 36 - original.completedThrough },
      (_, i) => original.completedThrough + 1 + i,
    ),
    automaticSubmissions: 0,
    selectiveRetriesAllowed: false,
    formalQualificationEligible: false,
    originalPacketMutationAllowed: false,
  };
}
export type PromptContinuationManifest = ReturnType<
  typeof promptContinuationManifest
>;

/** Release provenance can advance while the original runtime bundle stays fixed. */
export function requirePromptAmendmentControl(
  value: unknown,
  manifest: PromptAmendmentControlBinding,
  block: number,
  mode: "activation" | "cleanup",
) {
  check(
    [
      "audio_prompt_continuation_review_v1",
      "audio_prompt_continuation_review_v2",
      "audio_prompt_successor_review_v1",
    ].includes(manifest.review.version),
  );
  const window = manifest.review.windows.find((w) => w.block === block);
  check(window !== undefined);
  const v = fields(value, [
    "version",
    "operation",
    "target",
    "sourceSha",
    "deployedSha",
    "observedAt",
    "status",
    "mutationAttempted",
    "cleanup",
    "configurationPresent",
    "block",
    "window",
    "planSha256",
    "backendBundleSha256",
    "automaticIdentificationRequests",
    "failure",
  ]);
  check(
    v.version === "audio_prompt_comparison_control_v1" &&
      v.target === PROMPT_COMPARISON_PROJECT,
  );
  revision(v.sourceSha);
  check(
    v.automaticIdentificationRequests === 0 && v.failure === null &&
      typeof v.mutationAttempted === "boolean",
  );
  const observedAt = executionInstant(v.observedAt);
  check(observedAt >= executionInstant(manifest.preparedAt));
  if (mode === "activation") {
    const deployedSha = revision(
      manifest.review.version === "audio_prompt_continuation_review_v1"
        ? manifest.original.deployedSha
        : manifest.review.deployedSha,
    );
    check(
      v.sourceSha === manifest.tooling.commit &&
        v.deployedSha === deployedSha,
    );
    check(
      v.operation === "activate" &&
        ["active", "already_active"].includes(v.status as string),
    );
    check(v.configurationPresent === true && v.cleanup === "not_needed");
    check(observedAt >= executionInstant(manifest.original.lastCleanupAt));
  } else {
    check(
      v.operation === "deactivate" && v.status === "disabled" &&
        v.configurationPresent === false && v.cleanup === "verified_absent",
    );
    if (v.deployedSha !== null) revision(v.deployedSha);
    if (v.block === null) {
      check(
        v.window === null && v.planSha256 === null &&
          v.backendBundleSha256 === null && v.mutationAttempted === false,
      );
      return structuredClone(v);
    }
  }
  check(
    v.block === block && v.planSha256 === PLAN_SHA &&
      v.backendBundleSha256 === manifest.original.backendBundleSha256,
  );
  const w = fields(v.window, ["startsAt", "expiresAt"]);
  check(w.startsAt === window.startsAt && w.expiresAt === window.expiresAt);
  if (mode === "activation") {
    check(
      observedAt >= executionInstant(window.startsAt) &&
        observedAt < executionInstant(window.expiresAt),
    );
  }
  return structuredClone(v);
}

interface PromptAmendmentControlBinding {
  preparedAt: string;
  tooling: { commit: string };
  original: {
    deployedSha: string;
    lastCleanupAt: string;
    backendBundleSha256: string;
  };
  review: {
    version: string;
    deployedSha?: unknown;
    windows: { block: number; startsAt: string; expiresAt: string }[];
  };
}
export const requirePromptContinuationControl = (
  value: unknown,
  manifest: PromptContinuationManifest,
  block: number,
  mode: "activation" | "cleanup",
) => requirePromptAmendmentControl(value, manifest, block, mode);
