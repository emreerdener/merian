/** A new protocol; existing execution/continuation packets are never upgraded. */
import { resolve } from "node:path";
import {
  AUDIO_PROMPT_COMPARISON_PLAN as PLAN,
  AUDIO_PROMPT_COMPARISON_PLAN_SHA256 as PLAN_SHA,
} from "../../functions/identify-multimodal/comparison/promptPlan.ts";
import {
  executionInstant,
  promptPrivatePreflight,
} from "./audioPromptExecution.ts";
import {
  parseOriginalPromptBinding,
  requirePromptAmendmentControl,
} from "./audioPromptContinuationContract.ts";
import type { PromptSuccessorBinding } from "./audioPromptSuccessorEvidence.ts";
import { fingerprintJson } from "./evidence.ts";
import { hash, type SourceIdentity } from "./runContracts.ts";
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
const path = (v: unknown) => {
  check(typeof v === "string" && v.length <= 4096 && v === resolve(v));
  return v;
};
async function predecessorBinding(
  value: unknown,
): Promise<PromptSuccessorBinding> {
  const p = fields(value, [
    "originalDirectory",
    "continuationDirectory",
    "original",
    "continuation",
    "reports",
    "evidenceSha256",
  ]);
  const originalDirectory = path(p.originalDirectory);
  check(path(p.continuationDirectory) === originalDirectory + ".continuation");
  const original = parseOriginalPromptBinding(p.original);
  const c = fields(p.continuation, [
    "manifestSha256",
    "manifestFileSha256",
    "evidenceSha256",
    "completedThrough",
    "lastCompletedAt",
    "lastCleanupAt",
    "expiredAt",
  ]);
  for (
    const key of ["manifestSha256", "manifestFileSha256", "evidenceSha256"]
  ) hash(c[key]);
  integer(c.completedThrough, original.completedThrough + 1, 35);
  check((c.completedThrough as number) % 12 !== 0);
  check(
    executionInstant(c.lastCompletedAt) >=
      executionInstant(original.lastCleanupAt),
  );
  check(executionInstant(c.lastCompletedAt) < executionInstant(c.expiredAt));
  check(executionInstant(c.lastCleanupAt) >= executionInstant(c.expiredAt));
  const reports = fields(p.reports, ["original", "continuation"]);
  for (const key of ["original", "continuation"]) {
    const report = fields(reports[key], ["path", "sha256"]);
    path(report.path);
    hash(report.sha256);
  }
  hash(p.evidenceSha256);
  const { evidenceSha256, ...content } = p;
  check(await fingerprintJson(content) === evidenceSha256);
  return structuredClone(p) as unknown as PromptSuccessorBinding;
}
export async function promptSuccessorManifest(
  reviewValue: unknown,
  predecessorValue: unknown,
  toolingValue: unknown,
  now: number,
) {
  const predecessor = await predecessorBinding(predecessorValue);
  const tooling = fields(toolingValue, ["commit", "dirty", "digest", "sdk"]);
  revision(tooling.commit);
  hash(tooling.digest);
  check(tooling.dirty === false && tooling.sdk === "npm:@google/genai@2.23.0");
  const r = fields(reviewValue, [
    "version",
    "reviewedAt",
    "sourceSha",
    "deployedSha",
    "predecessorEvidenceSha256",
    "firstSlot",
    "windows",
    "privatePreflight",
    "noUnrecordedAttempts",
    "remainingNeverSubmitted",
    "pauseBetweenCompletedSlots",
    "analysisPolicy",
    "reports",
  ]);
  check(r.version === "audio_prompt_successor_review_v1");
  const reviewedAt = executionInstant(r.reviewedAt);
  check(
    Number.isFinite(now) && reviewedAt <= now &&
      reviewedAt >= executionInstant(predecessor.continuation.lastCleanupAt),
  );
  check(
    r.sourceSha === tooling.commit &&
      r.predecessorEvidenceSha256 === predecessor.evidenceSha256,
  );
  const deployedSha = revision(r.deployedSha);
  const firstSlot = predecessor.continuation.completedThrough + 1;
  check(r.firstSlot === firstSlot);
  for (
    const key of [
      "noUnrecordedAttempts",
      "remainingNeverSubmitted",
      "pauseBetweenCompletedSlots",
    ]
  ) check(r[key] === true);
  check(
    r.analysisPolicy ===
      "original_screening_rules_with_disclosed_interruptions",
  );
  const reports = fields(r.reports, ["original", "continuation"]);
  check(
    reports.original === predecessor.reports.original.path &&
      reports.continuation === predecessor.reports.continuation.path,
  );
  const privatePreflight = promptPrivatePreflight(
    r.privatePreflight,
    reviewedAt,
    reviewedAt - 300_000,
  );
  promptPrivatePreflight(privatePreflight, now, now - 300_000);
  const firstBlock = Math.ceil(firstSlot / 12);
  let previousStart = reviewedAt, previousEnd = reviewedAt;
  const pricedAt = executionInstant(predecessor.original.pricing.retrievedAt);
  const windows = array(r.windows, 4 - firstBlock, 4 - firstBlock).map(
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
    version: "audio_prompt_successor_manifest_v1" as const,
    preparedAt: new Date(now).toISOString(),
    planSha256: PLAN_SHA,
    predecessor,
    original: predecessor.original,
    tooling: structuredClone(tooling) as unknown as SourceIdentity,
    review: {
      ...r,
      analysisPolicy:
        "original_screening_rules_with_disclosed_interruptions" as const,
      version: "audio_prompt_successor_review_v1" as const,
      deployedSha,
      privatePreflight,
      windows,
      reports: {
        original: predecessor.reports.original.path,
        continuation: predecessor.reports.continuation.path,
      },
    },
    firstSlot,
    remainingSlots: Array.from(
      { length: 37 - firstSlot },
      (_, i) => firstSlot + i,
    ),
    automaticSubmissions: 0,
    selectiveRetriesAllowed: false,
    formalQualificationEligible: false,
    predecessorMutationAllowed: false,
    furtherSuccessorsAllowed: false,
  };
}
export type PromptSuccessorManifest = Awaited<
  ReturnType<typeof promptSuccessorManifest>
>;
export const requirePromptSuccessorControl = (
  value: unknown,
  manifest: PromptSuccessorManifest,
  block: number,
  mode: "activation" | "cleanup",
) => requirePromptAmendmentControl(value, manifest, block, mode);
