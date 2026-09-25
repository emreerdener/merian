/** Shared immutable ledger mechanics; protocol owners supply distinct versions
 * and parent bindings. This module performs no dispatch or hosted mutation. */
import { join } from "node:path";
import {
  executionInstant,
  promptPrivatePreflight,
} from "./audioPromptExecution.ts";
import type { OriginalPromptBinding } from "./audioPromptExecutionEvidence.ts";
import {
  admitBoundPromptObservation,
  promptControlFile,
  promptEvidenceFiles,
  promptObservationFile,
  promptSlotFile,
  promptSlotId,
  samePromptValue,
} from "./audioPromptExecutionEvidence.ts";
import { fingerprintJson } from "./evidence.ts";
import { claimJson, containedPath, exists, readBytes } from "./files.ts";
import { fields, requireCondition as check } from "./validation.ts";

export interface PromptLedgerContext {
  family: "audio_prompt_continuation" | "audio_prompt_successor";
  parentEvidenceField: "originalEvidenceSha256" | "predecessorEvidenceSha256";
  parentEvidenceSha256: string;
  previousFinishedAt: string;
  manifestSha256: string;
  manifest: {
    original: OriginalPromptBinding;
    firstSlot: number;
    remainingSlots: number[];
    review: {
      windows: { block: number; startsAt: string; expiresAt: string }[];
    };
  };
  read(path: string): Promise<unknown>;
  control(
    value: unknown,
    block: number,
    mode: "activation" | "cleanup",
  ): Record<string, unknown>;
}
type Completion = Awaited<ReturnType<typeof admitBoundPromptObservation>> & {
  slot: number;
};
/** Re-admit every stored completion; an uncompleted last claim is terminal for
 * further claiming. Cleanup is still recordable, including after a failure. */
export async function readPromptLedgerState(
  root: string,
  context: PromptLedgerContext,
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
    const activation = context.control(
      await read(activePath),
      w.block,
      "activation",
    );
    check(executionInstant(activation.observedAt) <= now);
    const cleanup = hasCleanup
      ? context.control(
        await read(cleanupPath),
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
  let previousFinishedAt = context.previousFinishedAt;
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
      context.parentEvidenceField,
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
      claim.version === `${context.family}_claim_v1` &&
        claim.manifestSha256 === manifestSha256 &&
        claim[context.parentEvidenceField] === context.parentEvidenceSha256 &&
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
        context.parentEvidenceField,
        "slot",
        "claimSha256",
        "finishedAt",
        "observationSha256",
        "admittedSha256",
        "admitted",
      ]);
      check(
        done.version === `${context.family}_completion_v1` &&
          done.manifestSha256 === manifestSha256 &&
          done[context.parentEvidenceField] === context.parentEvidenceSha256 &&
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
          context.parentEvidenceField,
          "slot",
          "claimSha256",
          "excludedAt",
          "reason",
          "automaticSubmissions",
        ]);
        check(
          exclusion.version === `${context.family}_exclusion_v1` &&
            exclusion.manifestSha256 === manifestSha256 &&
            exclusion[context.parentEvidenceField] ===
              context.parentEvidenceSha256 &&
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

export async function claimPromptLedgerSlot(
  root: string,
  context: PromptLedgerContext,
  slot: number,
  controlValue: unknown,
  now: number,
  witness: unknown,
) {
  const m = context.manifest;
  const state = await readPromptLedgerState(root, context, now);
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
  const activation = context.control(
    controlValue,
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
    witness,
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
    version: `${context.family}_claim_v1`,
    manifestSha256: context.manifestSha256,
    [context.parentEvidenceField]: context.parentEvidenceSha256,
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
}
export async function admitPromptLedgerSlot(
  root: string,
  context: PromptLedgerContext,
  slot: number,
  now: number,
  verify: () => Promise<void>,
) {
  const m = context.manifest;
  const state = await readPromptLedgerState(root, context, now);
  check(state.pending?.slot === slot && state.pending.excludedAt === null);
  const claim = state.pending.claim, block = Math.ceil(slot / 12);
  try {
    await verify();
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
      version: `${context.family}_completion_v1`,
      manifestSha256: context.manifestSha256,
      [context.parentEvidenceField]: context.parentEvidenceSha256,
      slot,
      claimSha256: await fingerprintJson(claim),
      ...observation,
    };
    await claimJson(join(root, promptSlotFile(slot, "completed")), done);
    return done;
  } catch {
    await claimJson(join(root, promptSlotFile(slot, "excluded")), {
      version: `${context.family}_exclusion_v1`,
      manifestSha256: context.manifestSha256,
      [context.parentEvidenceField]: context.parentEvidenceSha256,
      slot,
      claimSha256: await fingerprintJson(claim),
      excludedAt: new Date(now).toISOString(),
      reason: "observation_not_admitted",
      automaticSubmissions: 0,
    });
    throw new Error(`${context.family}_observation_excluded`);
  }
}
export async function closePromptLedgerBlock(
  root: string,
  context: PromptLedgerContext,
  block: number,
  controlValue: unknown,
  now: number,
) {
  const m = context.manifest;
  const activation = context.control(
    await context.read(promptControlFile(block, "activation")),
    block,
    "activation",
  );
  const cleanup = context.control(
    controlValue,
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
}
