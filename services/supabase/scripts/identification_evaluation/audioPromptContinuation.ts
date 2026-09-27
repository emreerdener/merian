/** Single offline sidecar for an expired, closed, certain-between-trials pause. */
import { dirname, join, resolve } from "node:path";
import {
  admitPromptLedgerSlot,
  claimPromptLedgerSlot,
  closePromptLedgerBlock,
  type PromptLedgerContext,
  readPromptLedgerState,
} from "./audioPromptLedger.ts";
import { identificationBundleDigest } from "../generate_identification_deployment_identity.ts";
import {
  renderAudioPromptComparisonPlan,
  renderSwiftAudioPromptComparisonPlan,
} from "../generate_audio_prompt_comparison_plan.ts";
import { assertOfflinePermissions } from "./admission.ts";
import {
  executionInstant,
  promptExecutionRepository,
  type PromptExecutionRuntime,
  promptExecutionRuntime,
} from "./audioPromptExecution.ts";
import {
  type PromptContinuationManifest,
  promptContinuationManifest,
  requirePromptContinuationControl,
} from "./audioPromptContinuationContract.ts";
import {
  auditOriginalPromptExecution,
  samePromptValue,
  withOriginalPromptLock,
} from "./audioPromptExecutionEvidence.ts";
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

export const promptContinuationDirectory = (original: string) =>
  resolve(original) + ".continuation";
export interface PromptContinuationRuntime extends PromptExecutionRuntime {
  bundle(): Promise<string>;
  verifyTables(): Promise<void>;
}
export const promptContinuationRuntime: PromptContinuationRuntime = {
  ...promptExecutionRuntime,
  bundle: identificationBundleDigest,
  verifyTables: async () => {
    for (
      const [path, rendered] of [
        [
          "services/supabase/functions/identify-multimodal/comparison/promptPlan.ts",
          await renderAudioPromptComparisonPlan(),
        ],
        [
          "apps/ios/Merian/Core/Network/Inference/DebugAudioPromptComparisonPlan.generated.swift",
          await renderSwiftAudioPromptComparisonPlan(),
        ],
      ]
    ) {
      check(
        await Deno.readTextFile(
          await containedPath(promptExecutionRepository, path),
        ) === rendered,
      );
    }
  },
};

export async function readPromptContinuation(root: string) {
  check(await Deno.realPath(root) === root);
  await privateDirectory(root);
  const read = async (path: string) =>
    readJson(await containedPath(root, path), 262_144);
  const freeze = fields(await read("freeze.json"), [
    "version",
    "manifestSha256",
    "manifestFileSha256",
  ]);
  check(freeze.version === "audio_prompt_continuation_freeze_v1");
  const bytes = await readBytes(await containedPath(root, "run.json"), 262_144);
  check(await fingerprintBytes(bytes) === freeze.manifestFileSha256);
  const raw = fields(
    JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
    [
      "version",
      "preparedAt",
      "planSha256",
      "original",
      "tooling",
      "review",
      "firstSlot",
      "remainingSlots",
      "automaticSubmissions",
      "selectiveRetriesAllowed",
      "formalQualificationEligible",
      "originalPacketMutationAllowed",
    ],
  );
  const manifest = promptContinuationManifest(
    raw.review,
    raw.original,
    raw.tooling,
    executionInstant(raw.preparedAt),
  );
  check(
    await samePromptValue(raw, manifest) &&
      await fingerprintJson(manifest) === freeze.manifestSha256,
  );
  return { manifest, manifestSha256: freeze.manifestSha256 as string, read };
}

async function verifyTooling(
  manifest: PromptContinuationManifest,
  runtime: PromptContinuationRuntime,
) {
  check(await samePromptValue(await runtime.source(), manifest.tooling));
  check(await runtime.bundle() === manifest.original.backendBundleSha256);
  await runtime.verifyTables();
}

export async function inspectPromptContinuationOriginal(
  directory: string,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  return withOriginalPromptLock(directory, async (root) => {
    const audit = await auditOriginalPromptExecution(
      root,
      runtime.now(),
      runtime,
    );
    return {
      original: audit.binding,
      remainingSlots: Array.from({
        length: 36 - audit.binding.completedThrough,
      }, (_, i) => audit.binding.completedThrough + 1 + i),
      automaticSubmissions: 0,
    };
  });
}

export async function preparePromptContinuation(
  directory: string,
  review: unknown,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  return withOriginalPromptLock(directory, async (original) => {
    const root = promptContinuationDirectory(original);
    check(
      !await exists(root) &&
        await Deno.realPath(dirname(root)) === dirname(root),
    );
    const now = runtime.now(),
      audit = await auditOriginalPromptExecution(original, now, runtime);
    const manifest = promptContinuationManifest(
      review,
      audit.binding,
      await runtime.source(),
      now,
    );
    await verifyTooling(manifest, runtime);
    // Canonical sibling name + create-only directory makes competing prepares
    // fail closed. No second sidecar or continuation-of-continuation is allowed.
    await Deno.mkdir(root, { mode: 0o700 });
    await syncDirectory(dirname(root));
    for (const name of ["slots", "controls", "observations"]) {
      await privateDirectory(join(root, name));
    }
    await claimJson(join(root, "run.json"), manifest);
    await claimJson(join(root, "freeze.json"), {
      version: "audio_prompt_continuation_freeze_v1",
      manifestSha256: await fingerprintJson(manifest),
      manifestFileSha256: await fingerprintBytes(
        await readBytes(join(root, "run.json"), 262_144),
      ),
    });
    // Detect edits outside the cooperative original lock before declaring ready.
    check(
      await samePromptValue(
        (await auditOriginalPromptExecution(original, now, runtime)).binding,
        manifest.original,
      ),
    );
    return manifest;
  });
}

type ContinuationRead = Awaited<ReturnType<typeof readPromptContinuation>>;
/** A view of the existing v1 ledger; does not upgrade or rewrite its schema. */
export function continuationLedger(
  context: ContinuationRead,
): PromptLedgerContext {
  const m = context.manifest;
  return {
    ...context,
    family: "audio_prompt_continuation",
    parentEvidenceField: "originalEvidenceSha256",
    parentEvidenceSha256: m.original.evidenceSha256,
    previousFinishedAt: m.original.lastCompletedAt,
    control: (value, block, mode) =>
      requirePromptContinuationControl(value, m, block, mode),
  };
}
const continuationState = (
  root: string,
  context: ContinuationRead,
  now: number,
) => readPromptLedgerState(root, continuationLedger(context), now);

async function originalMatches(
  original: string,
  m: PromptContinuationManifest,
  now: number,
  runtime: PromptContinuationRuntime,
) {
  const audit = await auditOriginalPromptExecution(original, now, runtime);
  check(await samePromptValue(audit.binding, m.original));
  return audit;
}

function withContinuation<T>(
  directory: string,
  work: (original: string, root: string) => Promise<T>,
) {
  return withOriginalPromptLock(directory, async (original) => {
    const root = promptContinuationDirectory(original);
    check(await Deno.realPath(root) === root);
    return withRunLock(root, () => work(original, root));
  });
}

export async function claimPromptContinuationSlot(
  directory: string,
  slot: number,
  controlValue: unknown,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  integer(slot, 1, 36);
  return withContinuation(directory, async (original, root) => {
    const context = await readPromptContinuation(root), now = runtime.now();
    await verifyTooling(context.manifest, runtime);
    await originalMatches(original, context.manifest, now, runtime);
    return claimPromptLedgerSlot(
      root,
      continuationLedger(context),
      slot,
      controlValue,
      now,
      await runtime.privatePreflight(),
    );
  });
}
export async function admitPromptContinuationSlot(
  directory: string,
  slot: number,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  integer(slot, 1, 36);
  return withContinuation(directory, async (original, root) => {
    const context = await readPromptContinuation(root), now = runtime.now();
    return admitPromptLedgerSlot(
      root,
      continuationLedger(context),
      slot,
      now,
      async () => {
        await verifyTooling(context.manifest, runtime);
        await originalMatches(original, context.manifest, now, runtime);
      },
    );
  });
}
/** Recovery does not depend on unchanged original files or current tooling. */
export async function closePromptContinuationBlock(
  directory: string,
  block: number,
  controlValue: unknown,
  now = Date.now(),
) {
  await assertOfflinePermissions();
  integer(block, 1, 3);
  const root = promptContinuationDirectory(directory);
  check(await Deno.realPath(root) === root);
  return withRunLock(
    root,
    async () =>
      closePromptLedgerBlock(
        root,
        continuationLedger(await readPromptContinuation(root)),
        block,
        controlValue,
        now,
      ),
  );
}

export async function reportPromptContinuation(
  directory: string,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  return withContinuation(directory, async (original, root) => {
    const context = await readPromptContinuation(root),
      m = context.manifest,
      now = runtime.now();
    await verifyTooling(m, runtime);
    const audit = await originalMatches(original, m, now, runtime);
    const state = await continuationState(root, context, now);
    const complete = m.original.completedThrough + state.rows.length === 36 &&
      state.pending === null;
    const cleanedUp = state.controls.every((c) => c.cleanup !== null);
    const known = [...audit.rows, ...state.rows].every((r) =>
      typeof r.admitted.primaryCost.estimatedPrimaryUpperUsd === "number" &&
      typeof r.admitted.tapToFirstRenderedFrameSeconds === "number"
    );
    return {
      version: "audio_prompt_continuation_evidence_report_v1",
      observedAt: new Date(now).toISOString(),
      execution: "amended_after_disclosed_interruption",
      original: m.original,
      continuationManifestSha256: context.manifestSha256,
      originalCompleted: m.original.completedThrough,
      continuationCompleted: state.rows.length,
      plannedSubmissions: 36,
      remainingSlots: m.remainingSlots.slice(state.rows.length),
      pendingOrExcludedSlot: state.pending?.slot ?? null,
      allActivatedBlocksVerifiedAbsent: cleanedUp,
      all36FirstAttemptsAdmitted: complete && cleanedUp,
      requiredMeasurementsKnown: known,
      completeMatchingEvidence: complete && cleanedUp && known,
      screeningRulesMayBeEvaluated: complete && cleanedUp && known,
      analysisPolicy: m.review.analysisPolicy,
      decision: complete && cleanedUp && known
        ? "requires_separate_frozen_screening_evaluation"
        : "inconclusive",
      originalRows: audit.rows,
      continuationRows: state.rows,
      originalControls: audit.controls,
      continuationControls: state.controls,
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

/** A derived report is a new external artifact, never a ledger mutation. */
export async function writePromptContinuationReport(
  directory: string,
  destination: string,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  const original = resolve(directory),
    sidecar = promptContinuationDirectory(original),
    output = resolve(destination);
  for (const root of [original, sidecar]) {
    check(output !== root && !output.startsWith(root + "/"));
  }
  const parent = dirname(output);
  check(await Deno.realPath(parent) === parent);
  await privateDirectory(parent);
  check(!await exists(output));
  const report = await reportPromptContinuation(original, runtime);
  await claimJson(output, report);
  return report;
}
