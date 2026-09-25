/** Single offline sidecar for an expired, closed, certain-between-trials pause. */
import { dirname, join, resolve } from "node:path";
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
  promptPrivatePreflight,
} from "./audioPromptExecution.ts";
import {
  type PromptContinuationManifest,
  promptContinuationManifest,
  requirePromptContinuationControl,
} from "./audioPromptContinuationContract.ts";
import {
  admitBoundPromptObservation,
  auditOriginalPromptExecution,
  promptControlFile,
  promptEvidenceFiles,
  promptObservationFile,
  promptSlotFile,
  promptSlotId,
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

async function readContinuation(root: string) {
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

type ContinuationRead = Awaited<ReturnType<typeof readContinuation>>;
type Completion = Awaited<ReturnType<typeof admitBoundPromptObservation>> & {
  slot: number;
};

/** Re-admit every stored completion; an uncompleted last claim is terminal for
 * further claiming. Cleanup is still recordable, including after a failure. */
async function continuationState(
  root: string,
  context: ContinuationRead,
  now: number,
) {
  const { manifest: m, manifestSha256, read } = context;
  const names = await promptEvidenceFiles(root, "slots");
  const count = names.filter((n) => n.endsWith(".claim.json")).length;
  check(count <= m.remainingSlots.length);
  const claims = Array.from({ length: count }, (_, i) => m.firstSlot + i);
  const allowed = claims.flatMap((s) =>
    ["claim", "completed", "excluded"].map((kind) =>
      `slot-${promptSlotId(s)}.${kind}.json`
    )
  );
  check(names.every((name) => allowed.includes(name)));
  const controlNames = await promptEvidenceFiles(root, "controls");
  const possibleControls = m.review.windows.flatMap((
    w,
  ) => [`block-${w.block}.activation.json`, `block-${w.block}.cleanup.json`]);
  check(controlNames.every((n) => possibleControls.includes(n)));
  const controls = [];
  for (const w of m.review.windows) {
    const activePath = promptControlFile(w.block, "activation"),
      cleanupPath = promptControlFile(w.block, "cleanup");
    const hasActive = await exists(join(root, activePath)),
      hasCleanup = await exists(join(root, cleanupPath));
    check(hasActive || !hasCleanup);
    if (!hasActive) continue;
    const activation = requirePromptContinuationControl(
      await read(activePath),
      m,
      w.block,
      "activation",
    );
    check(executionInstant(activation.observedAt) <= now);
    const cleanup = hasCleanup
      ? requirePromptContinuationControl(
        await read(cleanupPath),
        m,
        w.block,
        "cleanup",
      )
      : null;
    if (cleanup) {
      check(
        executionInstant(cleanup.observedAt) >=
            executionInstant(activation.observedAt) &&
          executionInstant(cleanup.observedAt) <= now,
      );
    }
    controls.push({ block: w.block, activation, cleanup });
  }
  const rows: Completion[] = [];
  let previousFinishedAt = m.original.lastCompletedAt;
  let pending: {
    slot: number;
    claim: Record<string, unknown>;
    excludedAt: string | null;
  } | null = null;
  for (const slot of claims) {
    const block = Math.ceil(slot / 12),
      window = m.review.windows.find((w) => w.block === block)!;
    const control = controls.find((c) => c.block === block);
    check(control !== undefined);
    const claim = fields(await read(promptSlotFile(slot, "claim")), [
      "version",
      "manifestSha256",
      "originalEvidenceSha256",
      "slot",
      "block",
      "claimedAt",
      "privatePreflight",
      "activationSha256",
      "expected",
    ]);
    const expected = {
      slot,
      app: m.original.app,
      backendBundleSha256: m.original.backendBundleSha256,
    };
    check(
      claim.version === "audio_prompt_continuation_claim_v1" &&
        claim.manifestSha256 === manifestSha256 &&
        claim.originalEvidenceSha256 === m.original.evidenceSha256 &&
        claim.slot === slot && claim.block === block,
    );
    check(await samePromptValue(claim.expected, expected));
    check(claim.activationSha256 === await fingerprintJson(control.activation));
    const claimedAt = executionInstant(claim.claimedAt),
      activationAt = executionInstant(control.activation.observedAt);
    check(
      claimedAt <= now &&
        claimedAt >=
          Math.max(
            executionInstant(previousFinishedAt),
            activationAt,
            executionInstant(window.startsAt),
          ) &&
        claimedAt + 151_000 < executionInstant(window.expiresAt),
    );
    promptPrivatePreflight(
      claim.privatePreflight,
      claimedAt,
      Math.max(executionInstant(previousFinishedAt), activationAt),
    );
    const hasDone = await exists(join(root, promptSlotFile(slot, "completed"))),
      hasExcluded = await exists(join(root, promptSlotFile(slot, "excluded")));
    check(!hasDone || !hasExcluded);
    let lastEventAt = claimedAt;
    if (hasDone) {
      const done = fields(await read(promptSlotFile(slot, "completed")), [
        "version",
        "manifestSha256",
        "originalEvidenceSha256",
        "slot",
        "claimSha256",
        "finishedAt",
        "observationSha256",
        "admittedSha256",
        "admitted",
      ]);
      check(
        done.version === "audio_prompt_continuation_completion_v1" &&
          done.manifestSha256 === manifestSha256 &&
          done.originalEvidenceSha256 === m.original.evidenceSha256 &&
          done.slot === slot &&
          done.claimSha256 === await fingerprintJson(claim),
      );
      const observation = await admitBoundPromptObservation(
        await readBytes(
          await containedPath(root, promptObservationFile(slot)),
          1_048_576,
        ),
        expected,
        m.original.pricing,
        claim.claimedAt as string,
        window.expiresAt,
        now,
      );
      for (
        const key of [
          "finishedAt",
          "observationSha256",
          "admittedSha256",
          "admitted",
        ] as const
      ) check(await samePromptValue(done[key], observation[key]));
      previousFinishedAt = observation.finishedAt;
      lastEventAt = executionInstant(previousFinishedAt);
      rows.push({ slot, ...observation });
    } else {
      check(slot === claims.at(-1));
      let excludedAt: string | null = null;
      if (hasExcluded) {
        const exclusion = fields(await read(promptSlotFile(slot, "excluded")), [
          "version",
          "manifestSha256",
          "originalEvidenceSha256",
          "slot",
          "claimSha256",
          "excludedAt",
          "reason",
          "automaticSubmissions",
        ]);
        check(
          exclusion.version === "audio_prompt_continuation_exclusion_v1" &&
            exclusion.manifestSha256 === manifestSha256 &&
            exclusion.originalEvidenceSha256 === m.original.evidenceSha256 &&
            exclusion.slot === slot &&
            exclusion.claimSha256 === await fingerprintJson(claim),
        );
        check(
          exclusion.reason === "observation_not_admitted" &&
            exclusion.automaticSubmissions === 0,
        );
        lastEventAt = executionInstant(exclusion.excludedAt);
        check(lastEventAt >= claimedAt && lastEventAt <= now);
        excludedAt = exclusion.excludedAt as string;
      }
      pending = { slot, claim, excludedAt };
    }
    if (control.cleanup) {
      check(executionInstant(control.cleanup.observedAt) >= lastEventAt);
    }
  }
  const observationNames = await promptEvidenceFiles(root, "observations");
  check(
    observationNames.every((name) =>
      claims.some((s) => name === `slot-${promptSlotId(s)}.jsonl`)
    ),
  );
  for (const control of controls) {
    const firstBlock = Math.ceil(m.firstSlot / 12);
    if (control.block > firstBlock) {
      const prior = controls.find((c) => c.block === control.block - 1);
      const priorDone = rows.find((r) => r.slot === (control.block - 1) * 12);
      check(
        prior?.cleanup !== null && prior?.cleanup !== undefined &&
          priorDone !== undefined,
      );
      check(
        executionInstant(prior.cleanup.observedAt) >=
          executionInstant(priorDone.finishedAt),
      );
      check(
        executionInstant(control.activation.observedAt) >=
          executionInstant(prior.cleanup.observedAt),
      );
    }
    // An activation written just before a crash may precede its first claim,
    // but no future block can appear before its full completion prefix.
    check(control.block <= Math.ceil((m.firstSlot + rows.length) / 12));
  }
  return { rows, pending, controls, previousFinishedAt };
}

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
    const context = await readContinuation(root), m = context.manifest;
    const now = runtime.now();
    await verifyTooling(m, runtime);
    await originalMatches(original, m, now, runtime);
    const state = await continuationState(root, context, now);
    check(
      state.pending === null && slot === m.firstSlot + state.rows.length &&
        slot <= 36,
    );
    const block = Math.ceil(slot / 12),
      window = m.review.windows.find((w) => w.block === block)!;
    check(
      now >= executionInstant(window.startsAt) &&
        now + 151_000 < executionInstant(window.expiresAt),
    );
    check(!await exists(join(root, promptControlFile(block, "cleanup"))));
    const activation = requirePromptContinuationControl(
      controlValue,
      m,
      block,
      "activation",
    );
    check(executionInstant(activation.observedAt) <= now);
    if (block > Math.ceil(m.firstSlot / 12)) {
      const previous = state.controls.find((c) => c.block === block - 1);
      check(previous?.cleanup !== null && previous?.cleanup !== undefined);
      check(state.rows.some((r) => r.slot === (block - 1) * 12));
      check(
        executionInstant(activation.observedAt) >=
          executionInstant(previous.cleanup.observedAt),
      );
    }
    const privatePreflight = promptPrivatePreflight(
      await runtime.privatePreflight(),
      now,
      Math.max(
        executionInstant(state.previousFinishedAt),
        executionInstant(activation.observedAt),
      ),
    );
    const path = promptControlFile(block, "activation");
    if (await exists(join(root, path))) {
      check(await samePromptValue(await context.read(path), activation));
    } else await claimJson(join(root, path), activation);
    const claim = {
      version: "audio_prompt_continuation_claim_v1",
      manifestSha256: context.manifestSha256,
      originalEvidenceSha256: m.original.evidenceSha256,
      slot,
      block,
      claimedAt: new Date(now).toISOString(),
      privatePreflight,
      activationSha256: await fingerprintJson(activation),
      expected: {
        slot,
        app: m.original.app,
        backendBundleSha256: m.original.backendBundleSha256,
      },
    };
    await claimJson(join(root, promptSlotFile(slot, "claim")), claim);
    return claim;
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
    const context = await readContinuation(root),
      m = context.manifest,
      now = runtime.now();
    const state = await continuationState(root, context, now);
    check(state.pending?.slot === slot && state.pending.excludedAt === null);
    const claim = state.pending.claim, block = Math.ceil(slot / 12);
    try {
      await verifyTooling(m, runtime);
      await originalMatches(original, m, now, runtime);
      check(!state.controls.find((c) => c.block === block)?.cleanup);
      const observation = await admitBoundPromptObservation(
        await readBytes(
          await containedPath(root, promptObservationFile(slot)),
          1_048_576,
        ),
        {
          slot,
          app: m.original.app,
          backendBundleSha256: m.original.backendBundleSha256,
        },
        m.original.pricing,
        claim.claimedAt as string,
        m.review.windows.find((w) => w.block === block)!.expiresAt,
        now,
      );
      const done = {
        version: "audio_prompt_continuation_completion_v1",
        manifestSha256: context.manifestSha256,
        originalEvidenceSha256: m.original.evidenceSha256,
        slot,
        claimSha256: await fingerprintJson(claim),
        ...observation,
      };
      await claimJson(join(root, promptSlotFile(slot, "completed")), done);
      return done;
    } catch {
      await claimJson(join(root, promptSlotFile(slot, "excluded")), {
        version: "audio_prompt_continuation_exclusion_v1",
        manifestSha256: context.manifestSha256,
        originalEvidenceSha256: m.original.evidenceSha256,
        slot,
        claimSha256: await fingerprintJson(claim),
        excludedAt: new Date(now).toISOString(),
        reason: "observation_not_admitted",
        automaticSubmissions: 0,
      });
      throw new Error("audio_prompt_continuation_observation_excluded");
    }
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
  return withRunLock(root, async () => {
    const context = await readContinuation(root), m = context.manifest;
    const activation = requirePromptContinuationControl(
      await context.read(promptControlFile(block, "activation")),
      m,
      block,
      "activation",
    );
    const cleanup = requirePromptContinuationControl(
      controlValue,
      m,
      block,
      "cleanup",
    );
    let after = executionInstant(activation.observedAt);
    for (
      let slot = Math.max(m.firstSlot, (block - 1) * 12 + 1);
      slot <= block * 12;
      slot++
    ) {
      for (
        const [kind, key] of [["claim", "claimedAt"], [
          "completed",
          "finishedAt",
        ], ["excluded", "excludedAt"]]
      ) {
        if (await exists(join(root, promptSlotFile(slot, kind)))) {
          const v = await context.read(promptSlotFile(slot, kind)) as Record<
            string,
            unknown
          >;
          after = Math.max(after, executionInstant(v[key]));
        }
      }
    }
    check(
      executionInstant(cleanup.observedAt) >= after &&
        executionInstant(cleanup.observedAt) <= now,
    );
    await claimJson(join(root, promptControlFile(block, "cleanup")), cleanup);
    return cleanup;
  });
}

export async function reportPromptContinuation(
  directory: string,
  runtime: PromptContinuationRuntime = promptContinuationRuntime,
) {
  await assertOfflinePermissions();
  return withContinuation(directory, async (original, root) => {
    const context = await readContinuation(root),
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
