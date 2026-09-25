/** One fixed, offline successor after a closed first continuation. No dispatch. */
import { dirname, join, resolve } from "node:path";
import { assertOfflinePermissions } from "./admission.ts";
import { executionInstant } from "./audioPromptExecution.ts";
import {
  type PromptContinuationRuntime,
  promptContinuationRuntime,
} from "./audioPromptContinuation.ts";
import { samePromptValue } from "./audioPromptExecutionEvidence.ts";
import {
  admitPromptLedgerSlot,
  claimPromptLedgerSlot,
  closePromptLedgerBlock,
  type PromptLedgerContext,
  readPromptLedgerState,
} from "./audioPromptLedger.ts";
import {
  promptSuccessorManifest,
  requirePromptSuccessorControl,
} from "./audioPromptSuccessorContract.ts";
import {
  auditPromptSuccessorParents,
  type PromptReportPaths,
  promptSuccessorBindingSummary,
  promptSuccessorDirectory,
  withPromptSuccessorParents,
} from "./audioPromptSuccessorEvidence.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import {
  claimJson,
  containedPath,
  exists,
  privateDirectory,
  readBytes,
  readJson,
  syncDirectory,
  withRunLock,
} from "./files.ts";
import { fields, integer, requireCondition as check } from "./validation.ts";

async function readSuccessor(root: string) {
  check(await Deno.realPath(root) === root);
  await privateDirectory(root);
  const allowed = new Set([
    "run.json",
    "freeze.json",
    ".lock",
    "slots",
    "controls",
    "observations",
  ]);
  for await (const entry of Deno.readDir(root)) {
    check(allowed.has(entry.name) && !entry.isSymlink);
  }
  const read = async (path: string) =>
    readJson(await containedPath(root, path), 262_144);
  const freeze = fields(await read("freeze.json"), [
    "version",
    "manifestSha256",
    "manifestFileSha256",
  ]);
  check(freeze.version === "audio_prompt_successor_freeze_v1");
  const bytes = await readBytes(await containedPath(root, "run.json"), 262_144);
  check(await fingerprintBytes(bytes) === freeze.manifestFileSha256);
  const raw = fields(
    JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
    [
      "version",
      "preparedAt",
      "planSha256",
      "predecessor",
      "original",
      "tooling",
      "review",
      "firstSlot",
      "remainingSlots",
      "automaticSubmissions",
      "selectiveRetriesAllowed",
      "formalQualificationEligible",
      "predecessorMutationAllowed",
      "furtherSuccessorsAllowed",
    ],
  );
  const manifest = await promptSuccessorManifest(
    raw.review,
    raw.predecessor,
    raw.tooling,
    executionInstant(raw.preparedAt),
  );
  check(
    await samePromptValue(raw, manifest) &&
      await fingerprintJson(manifest) === freeze.manifestSha256,
  );
  const context = {
    manifest,
    manifestSha256: freeze.manifestSha256 as string,
    read,
  };
  const ledger: PromptLedgerContext = {
    ...context,
    family: "audio_prompt_successor",
    parentEvidenceField: "predecessorEvidenceSha256",
    parentEvidenceSha256: manifest.predecessor.evidenceSha256,
    previousFinishedAt: manifest.predecessor.continuation.lastCompletedAt,
    control: (value, block, mode) =>
      requirePromptSuccessorControl(value, manifest, block, mode),
  };
  return { ...context, ledger };
}
type SuccessorRead = Awaited<ReturnType<typeof readSuccessor>>;

async function verify(
  original: string,
  continuation: string,
  context: SuccessorRead,
  runtime: PromptContinuationRuntime,
  now: number,
) {
  const m = context.manifest;
  check(
    m.predecessor.originalDirectory === original &&
      m.predecessor.continuationDirectory === continuation,
  );
  check(await samePromptValue(await runtime.source(), m.tooling));
  check(await runtime.bundle() === m.original.backendBundleSha256);
  await runtime.verifyTables();
  const audit = await auditPromptSuccessorParents(
    original,
    continuation,
    m.review.reports,
    now,
    runtime,
  );
  check(await samePromptValue(audit.binding, m.predecessor));
  return audit;
}
function withSuccessor<T>(
  directory: string,
  work: (original: string, continuation: string, root: string) => Promise<T>,
) {
  return withPromptSuccessorParents(
    directory,
    async (original, continuation) => {
      const root = promptSuccessorDirectory(original);
      check(await Deno.realPath(root) === root);
      return withRunLock(root, () => work(original, continuation, root));
    },
  );
}
export async function inspectPromptSuccessor(
  directory: string,
  reports: PromptReportPaths,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  return withPromptSuccessorParents(
    directory,
    async (original, continuation) => {
      const audit = await auditPromptSuccessorParents(
        original,
        continuation,
        reports,
        runtime.now(),
        runtime,
      );
      return {
        predecessor: promptSuccessorBindingSummary(audit.binding),
        remainingSlots: Array.from({
          length: 36 - audit.binding.continuation.completedThrough,
        }, (_, i) => audit.binding.continuation.completedThrough + 1 + i),
        automaticSubmissions: 0,
      };
    },
  );
}
export async function preparePromptSuccessor(
  directory: string,
  reviewValue: unknown,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  return withPromptSuccessorParents(
    directory,
    async (original, continuation) => {
      const root = promptSuccessorDirectory(original);
      check(
        !await exists(root) &&
          await Deno.realPath(dirname(root)) === dirname(root),
      );
      const review = fields(reviewValue, [
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
      const reports = fields(review.reports, ["original", "continuation"]);
      check(
        typeof reports.original === "string" &&
          typeof reports.continuation === "string",
      );
      const now = runtime.now();
      const audit = await auditPromptSuccessorParents(
        original,
        continuation,
        { original: reports.original, continuation: reports.continuation },
        now,
        runtime,
      );
      const manifest = await promptSuccessorManifest(
        review,
        audit.binding,
        await runtime.source(),
        now,
      );
      check(await runtime.bundle() === manifest.original.backendBundleSha256);
      await runtime.verifyTables();
      // A fixed sibling plus create-only directory permits exactly one successor.
      // Existing empty/torn/failed packets are terminal and are never replaced.
      await Deno.mkdir(root, { mode: 0o700 });
      await syncDirectory(dirname(root));
      for (
        const name of ["slots", "controls", "observations"]
      ) await privateDirectory(join(root, name));
      await claimJson(join(root, "run.json"), manifest);
      await claimJson(join(root, "freeze.json"), {
        version: "audio_prompt_successor_freeze_v1",
        manifestSha256: await fingerprintJson(manifest),
        manifestFileSha256: await fingerprintBytes(
          await readBytes(join(root, "run.json"), 262_144),
        ),
      });
      await verify(
        original,
        continuation,
        await readSuccessor(root),
        runtime,
        now,
      );
      return manifest;
    },
  );
}
export async function claimPromptSuccessorSlot(
  directory: string,
  slot: number,
  control: unknown,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  integer(slot, 1, 36);
  return withSuccessor(directory, async (original, continuation, root) => {
    const context = await readSuccessor(root), now = runtime.now();
    await verify(original, continuation, context, runtime, now);
    return claimPromptLedgerSlot(
      root,
      context.ledger,
      slot,
      control,
      now,
      await runtime.privatePreflight(),
    );
  });
}
export async function admitPromptSuccessorSlot(
  directory: string,
  slot: number,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  integer(slot, 1, 36);
  return withSuccessor(directory, async (original, continuation, root) => {
    const context = await readSuccessor(root), now = runtime.now();
    return admitPromptLedgerSlot(root, context.ledger, slot, now, async () => {
      await verify(original, continuation, context, runtime, now);
    });
  });
}
/** Cleanup can be recorded even after parent or tooling drift; it never resumes. */
export async function closePromptSuccessorBlock(
  directory: string,
  block: number,
  control: unknown,
  now = Date.now(),
) {
  await assertOfflinePermissions();
  integer(block, 1, 3);
  const root = promptSuccessorDirectory(directory);
  check(await Deno.realPath(root) === root);
  return withRunLock(
    root,
    async () =>
      closePromptLedgerBlock(
        root,
        (await readSuccessor(root)).ledger,
        block,
        control,
        now,
      ),
  );
}
export async function reportPromptSuccessor(
  directory: string,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  return withSuccessor(directory, async (original, continuation, root) => {
    const context = await readSuccessor(root),
      m = context.manifest,
      now = runtime.now();
    const audit = await verify(original, continuation, context, runtime, now);
    const state = await readPromptLedgerState(root, context.ledger, now);
    const rows = [
      ...audit.originalRows,
      ...audit.continuationRows,
      ...state.rows,
    ];
    const complete = rows.length === 36 && rows.every((row, i) =>
      row.slot === i + 1
    ) && state.pending === null;
    const cleaned = state.controls.every((c) => c.cleanup !== null);
    const known = rows.every((r) =>
      typeof r.admitted.primaryCost.estimatedPrimaryUpperUsd === "number" &&
      typeof r.admitted.tapToFirstRenderedFrameSeconds === "number" &&
      typeof r.admitted.measurement.serverTimingMs.provider === "number" &&
      typeof r.admitted.measurement.serverTimingMs.edge_total === "number" &&
      typeof r.admitted.nativeOutcome.confidenceScore === "number"
    );
    return {
      version: "audio_prompt_successor_evidence_report_v1",
      observedAt: new Date(now).toISOString(),
      execution: "amended_after_two_disclosed_interruptions",
      analysisPolicy: m.review.analysisPolicy,
      predecessor: promptSuccessorBindingSummary(m.predecessor),
      successorManifestSha256: context.manifestSha256,
      originalCompleted: audit.originalRows.length,
      continuationCompleted: audit.continuationRows.length,
      successorCompleted: state.rows.length,
      plannedSubmissions: 36,
      remainingSlots: m.remainingSlots.slice(state.rows.length),
      pendingOrExcludedSlot: state.pending?.slot ?? null,
      allActivatedBlocksVerifiedAbsent: cleaned,
      all36FirstAttemptsAdmitted: complete && cleaned,
      requiredMeasurementsKnown: known,
      completeMatchingEvidence: complete && cleaned && known,
      screeningRulesMayBeEvaluated: complete && cleaned && known,
      decision: complete && cleaned && known
        ? "requires_separate_frozen_screening_evaluation"
        : "inconclusive",
      originalRows: audit.originalRows,
      continuationRows: audit.continuationRows,
      successorRows: state.rows,
      originalControls: audit.originalControls,
      continuationControls: audit.continuationControls,
      successorControls: state.controls,
      retainedReportProvenance:
        "opaque_byte_bindings_only_not_an_independent_attestation",
      submissionAbsenceEvidence:
        "local_evidence_and_operator_witness_only_not_independent_provider_audit",
      controlProvenance:
        "receipt_bindings_only_external_workflow_provenance_must_be_verified_separately",
      formalQualificationEligible: false,
      productionPromotionAuthorized: false,
      automaticSubmissions: 0,
    };
  });
}
export async function writePromptSuccessorReport(
  directory: string,
  destination: string,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  const original = resolve(directory), output = resolve(destination);
  for (
    const root of [
      original,
      original + ".continuation",
      promptSuccessorDirectory(original),
    ]
  ) check(output !== root && !output.startsWith(root + "/"));
  const parent = dirname(output);
  check(await Deno.realPath(parent) === parent);
  await privateDirectory(parent);
  check(!await exists(output));
  const report = await reportPromptSuccessor(original, runtime);
  await claimJson(output, report);
  return report;
}
