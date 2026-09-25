/** Offline run bindings and first-attempt ledger. No account or provider access. */
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  AUDIO_PROMPT_COMPARISON_PLAN as PLAN,
  AUDIO_PROMPT_COMPARISON_PLAN_SHA256 as PLAN_SHA,
} from "../../functions/identify-multimodal/comparison/promptPlan.ts";
import { IDENTIFICATION_BUNDLE_SHA256 } from "../../functions/identify-multimodal/deploymentIdentity.ts";
import { PROMPT_COMPARISON_PROJECT } from "../control_audio_prompt_comparison.ts";
import { assertOfflinePermissions } from "./admission.ts";
import { admitAudioPromptComparisonWindow } from "./audioPromptComparisonWindow.ts";
import { parseComparisonWindowExpectation } from "./comparisonWindow.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import {
  claimJson,
  containedPath,
  exists,
  privateDirectory,
  readBytes,
  readJson,
  sourceIdentity,
  withRunLock,
} from "./files.ts";
import { hash, parsePricing, type SourceIdentity } from "./runContracts.ts";
import {
  array,
  fields,
  integer,
  requireCondition as check,
} from "./validation.ts";

export const promptExecutionRepository = fileURLToPath(
  new URL("../../../..", import.meta.url),
);
const REVISION = /^[a-f0-9]{40}$/;
export function executionInstant(value: unknown): number {
  check(
    typeof value === "string" &&
      /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value),
  );
  const time = Date.parse(value);
  check(Number.isFinite(time) && new Date(time).toISOString() === value);
  return time;
}

/** Operator witness after a private check, not an auth/session attestation.
 * The actual authenticated-owner and consent checks remain server-owned. */
export function promptPrivatePreflight(
  value: unknown,
  now: number,
  notBefore: number,
) {
  const v = fields(value, [
    "version",
    "checkedAt",
    "ownerMatchesReviewedConfiguration",
    "sameReviewedOwner",
    "consentCurrent",
    "appMatchesReview",
    "foreground",
  ]);
  check(v.version === "audio_prompt_private_preflight_v1");
  const checkedAt = executionInstant(v.checkedAt);
  check(
    checkedAt >= notBefore && checkedAt <= now && now - checkedAt <= 300_000,
  );
  for (
    const key of [
      "ownerMatchesReviewedConfiguration",
      "sameReviewedOwner",
      "consentCurrent",
      "appMatchesReview",
      "foreground",
    ]
  ) check(v[key] === true);
  return structuredClone(v);
}

/** Exact case-only paths; never accept a swapped, added, linked or missing WAV. */
export async function verifyPromptExecutionAssets(
  root: string,
  assignments: readonly {
    caseId: string;
    sourceWavSha256: string;
    sourceByteLength: number;
  }[] = PLAN.assignments,
) {
  const assets = await containedPath(root, "assets");
  await privateDirectory(assets);
  const cases = new Map(assignments.map((a) => [a.caseId, a]));
  check(cases.size === 6);
  const names: string[] = [];
  for await (const entry of Deno.readDir(assets)) {
    check(entry.isFile && !entry.isSymlink);
    names.push(entry.name);
  }
  check(
    names.sort().join(",") ===
      [...cases.keys()].map((id) => id + ".wav").sort().join(","),
  );
  for (const c of cases.values()) {
    check(/^c[0-9]{4}$/.test(c.caseId));
    hash(c.sourceWavSha256);
    const path = await containedPath(root, "assets/" + c.caseId + ".wav");
    const stat = await Deno.lstat(path);
    check(stat.mode !== null && (stat.mode & 0o077) === 0);
    const bytes = await readBytes(path, 44 + 44100 * 15 * 2);
    check(
      bytes.length === c.sourceByteLength &&
        await fingerprintBytes(bytes) === c.sourceWavSha256,
    );
  }
}

/** Deliberately excludes owner IDs, session data, credentials and prose. */
export function parsePromptExecutionReview(value: unknown) {
  const v = fields(value, [
    "version",
    "reviewedAt",
    "sourceSha",
    "deployedSha",
    "app",
    "backendBundleSha256",
    "pricing",
    "windows",
    "privatePreflight",
  ]);
  check(v.version === "audio_prompt_execution_review_v1");
  const reviewedAt = executionInstant(v.reviewedAt);
  check(typeof v.sourceSha === "string" && REVISION.test(v.sourceSha));
  check(typeof v.deployedSha === "string" && REVISION.test(v.deployedSha));
  const expected = parseComparisonWindowExpectation({
    slot: 1,
    app: v.app,
    backendBundleSha256: v.backendBundleSha256,
  }, 36);
  check(
    expected.app.sourceState === "clean" &&
      expected.app.sourceRevision === v.sourceSha,
  );
  check(expected.backendBundleSha256 === IDENTIFICATION_BUNDLE_SHA256);
  const pricing = parsePricing(v.pricing);
  const pricedAt = executionInstant(pricing.retrievedAt);
  check(pricedAt <= reviewedAt);
  let previousStart = reviewedAt, previousEnd = reviewedAt;
  const windows = array(v.windows, 3, 3).map((raw, index) => {
    const w = fields(raw, ["block", "startsAt", "expiresAt"]);
    check(w.block === index + 1);
    const start = executionInstant(w.startsAt),
      end = executionInstant(w.expiresAt);
    check(start >= reviewedAt && start >= previousStart && end > previousEnd);
    check(end > start && end - start <= 7_200_000);
    check(
      start >= Date.parse(PLAN.startsNotBefore) &&
        end <= Date.parse(PLAN.expiresNotAfter),
    );
    check(end - pricedAt <= 7 * 86_400_000);
    previousStart = start;
    previousEnd = end;
    return {
      block: index + 1,
      startsAt: w.startsAt as string,
      expiresAt: w.expiresAt as string,
    };
  });
  return {
    version: "audio_prompt_execution_review_v1" as const,
    reviewedAt: v.reviewedAt as string,
    sourceSha: v.sourceSha,
    deployedSha: v.deployedSha,
    app: expected.app,
    backendBundleSha256: expected.backendBundleSha256,
    pricing,
    windows,
    privatePreflight: promptPrivatePreflight(
      v.privatePreflight,
      reviewedAt,
      reviewedAt - 300_000,
    ),
  };
}
export type PromptExecutionReview = ReturnType<
  typeof parsePromptExecutionReview
>;

export function promptExecutionManifest(
  reviewValue: unknown,
  implementation: SourceIdentity,
  now: number,
) {
  const review = parsePromptExecutionReview(reviewValue);
  check(Number.isFinite(now) && executionInstant(review.reviewedAt) <= now);
  check(now < executionInstant(review.windows[0].expiresAt));
  promptPrivatePreflight(review.privatePreflight, now, now - 300_000);
  check(
    implementation.commit === review.sourceSha &&
      implementation.dirty === false,
  );
  hash(implementation.digest);
  check(implementation.sdk === "npm:@google/genai@2.23.0");
  return {
    version: "audio_prompt_execution_manifest_v1" as const,
    preparedAt: new Date(now).toISOString(),
    planSha256: PLAN_SHA,
    preparationSha256: PLAN.preparationSha256,
    designSha256: PLAN.designSha256,
    review,
    implementation,
    assignments: PLAN.assignments,
    plannedSubmissions: 36,
    selectiveRetriesAllowed: false,
    automaticSubmissions: 0,
    formalQualificationEligible: false,
    ownerBinding: "private_production_secret_only",
  };
}
export type PromptExecutionManifest = ReturnType<
  typeof promptExecutionManifest
>;

/** Sanitized management-plane evidence is necessary, not a runtime attestation. */
export function requirePromptControl(
  value: unknown,
  manifest: PromptExecutionManifest,
  block: number,
  mode: "activation" | "cleanup",
) {
  integer(block, 1, 3);
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
  check(
    typeof v.sourceSha === "string" && REVISION.test(v.sourceSha) &&
      v.automaticIdentificationRequests === 0 && v.failure === null,
  );
  check(typeof v.mutationAttempted === "boolean");
  const observedAt = executionInstant(v.observedAt);
  check(observedAt >= executionInstant(manifest.preparedAt));
  if (mode === "activation") {
    check(v.sourceSha === manifest.review.sourceSha);
    check(
      v.operation === "activate" &&
        ["active", "already_active"].includes(v.status as string),
    );
    check(
      v.deployedSha === manifest.review.deployedSha &&
        v.configurationPresent === true && v.cleanup === "not_needed",
    );
  } else {
    check(
      v.operation === "deactivate" && v.status === "disabled" &&
        v.configurationPresent === false && v.cleanup === "verified_absent",
    );
    check(
      v.deployedSha === null ||
        (typeof v.deployedSha === "string" && REVISION.test(v.deployedSha)),
    );
    if (v.block === null) {
      // Already absent: the control intentionally has no private config to parse.
      check(
        v.window === null && v.planSha256 === null &&
          v.backendBundleSha256 === null,
      );
      check(v.mutationAttempted === false);
      return structuredClone(v);
    }
  }
  check(
    v.block === block && v.planSha256 === PLAN_SHA &&
      v.backendBundleSha256 === manifest.review.backendBundleSha256,
  );
  const w = fields(v.window, ["startsAt", "expiresAt"]),
    expected = manifest.review.windows[block - 1];
  check(w.startsAt === expected.startsAt && w.expiresAt === expected.expiresAt);
  if (mode === "activation") {
    check(
      observedAt >= executionInstant(w.startsAt) &&
        observedAt < executionInstant(w.expiresAt),
    );
  }
  return structuredClone(v);
}

export async function readPromptExecution(root: string) {
  check(await Deno.realPath(root) === root);
  await privateDirectory(root);
  const read = async (path: string) =>
    await readJson(await containedPath(root, path), 262_144);
  const freeze = fields(await read("freeze.json"), [
    "version",
    "manifestSha256",
    "manifestFileSha256",
  ]);
  check(freeze.version === "audio_prompt_execution_freeze_v1");
  const bytes = await readBytes(await containedPath(root, "run.json"), 262_144);
  check(await fingerprintBytes(bytes) === freeze.manifestFileSha256);
  const raw = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  );
  check(await fingerprintJson(raw) === freeze.manifestSha256);
  const v = fields(raw, [
    "version",
    "preparedAt",
    "planSha256",
    "preparationSha256",
    "designSha256",
    "review",
    "implementation",
    "assignments",
    "plannedSubmissions",
    "selectiveRetriesAllowed",
    "automaticSubmissions",
    "formalQualificationEligible",
    "ownerBinding",
  ]);
  const source = fields(v.implementation, [
    "commit",
    "dirty",
    "digest",
    "sdk",
  ]) as unknown as SourceIdentity;
  const manifest = promptExecutionManifest(
    v.review,
    source,
    executionInstant(v.preparedAt),
  );
  check(await fingerprintJson(manifest) === freeze.manifestSha256);
  await privateDirectory(await containedPath(root, "slots"));
  await privateDirectory(await containedPath(root, "controls"));
  return { manifest, manifestSha256: freeze.manifestSha256 as string, read };
}
const slotFile = (slot: number, kind: "claim" | "completed" | "excluded") =>
  `slots/slot-${String(slot).padStart(2, "0")}.${kind}.json`;
const controlFile = (block: number, mode: "activation" | "cleanup") =>
  `controls/block-${block}.${mode}.json`;

export interface PromptExecutionRuntime {
  now(): number;
  source(): Promise<SourceIdentity>;
  privatePreflight(): Promise<unknown>;
  verifyAssets(root: string): Promise<void>;
}
export const promptExecutionRuntime: PromptExecutionRuntime = {
  now: () => Date.now(),
  source: () => sourceIdentity(promptExecutionRepository),
  privatePreflight: () =>
    Promise.reject(new Error("private_preflight_required")),
  verifyAssets: (root) => verifyPromptExecutionAssets(root),
};

/** One immutable claim BEFORE Identify. A claim without completion blocks all
 * subsequent slots; there is deliberately no reset, retry or replacement API. */
export async function claimPromptExecutionSlot(
  directory: string,
  slot: number,
  controlValue: unknown,
  runtime: PromptExecutionRuntime = promptExecutionRuntime,
) {
  await assertOfflinePermissions();
  integer(slot, 1, 36);
  const root = resolve(directory);
  await privateDirectory(root);
  return await withRunLock(root, async () => {
    const { manifest, manifestSha256, read } = await readPromptExecution(root);
    check(
      await fingerprintJson(await runtime.source()) ===
        await fingerprintJson(manifest.implementation),
    );
    await runtime.verifyAssets(root);
    const assignment = PLAN.assignments[slot - 1], block = assignment.block;
    const now = runtime.now(), window = manifest.review.windows[block - 1];
    check(
      now >= executionInstant(window.startsAt) &&
        now + 151_000 < executionInstant(window.expiresAt),
    );
    check(!await exists(join(root, controlFile(block, "cleanup"))));
    const activation = requirePromptControl(
      controlValue,
      manifest,
      block,
      "activation",
    );
    check(executionInstant(activation.observedAt) <= now);
    let previousFinishedAt = executionInstant(manifest.preparedAt);
    for (let i = 1; i < slot; i++) {
      check(!await exists(join(root, slotFile(i, "excluded"))));
      const claim = await read(slotFile(i, "claim"));
      const done = fields(await read(slotFile(i, "completed")), [
        "version",
        "manifestSha256",
        "slot",
        "claimSha256",
        "finishedAt",
        "observationSha256",
        "admittedSha256",
        "admitted",
      ]);
      check(
        done.version === "audio_prompt_execution_completion_v1" &&
          done.manifestSha256 === manifestSha256 && done.slot === i,
      );
      check(
        done.claimSha256 === await fingerprintJson(claim) &&
          done.admittedSha256 === await fingerprintJson(done.admitted),
      );
      previousFinishedAt = executionInstant(done.finishedAt);
      check(previousFinishedAt <= now);
    }
    for (let i = slot; i <= 36; i++) {
      check(
        !await exists(join(root, slotFile(i, "claim"))) &&
          !await exists(join(root, slotFile(i, "completed"))) &&
          !await exists(join(root, slotFile(i, "excluded"))),
      );
    }
    if (block > 1) {
      const cleanup = requirePromptControl(
        await read(controlFile(block - 1, "cleanup")),
        manifest,
        block - 1,
        "cleanup",
      );
      // Prior cleanup must follow the previous block's final window, not this
      // block's earlier slots. Validate against its actual final completion.
      const prior = await read(slotFile((block - 1) * 12, "completed")) as {
        finishedAt: string;
      };
      check(
        executionInstant(cleanup.observedAt) >=
          executionInstant(prior.finishedAt),
      );
      check(
        executionInstant(activation.observedAt) >=
          executionInstant(cleanup.observedAt),
      );
    }
    const privatePreflight = promptPrivatePreflight(
      await runtime.privatePreflight(),
      now,
      Math.max(previousFinishedAt, executionInstant(activation.observedAt)),
    );
    const path = join(root, controlFile(block, "activation"));
    if (await exists(path)) {
      check(
        await fingerprintJson(await read(controlFile(block, "activation"))) ===
          await fingerprintJson(activation),
      );
    } else await claimJson(path, activation);
    check(previousFinishedAt <= now);
    const claim = {
      version: "audio_prompt_execution_claim_v1",
      manifestSha256,
      slot,
      block,
      claimedAt: new Date(now).toISOString(),
      privatePreflight,
      activationSha256: await fingerprintJson(activation),
      expected: {
        slot,
        app: manifest.review.app,
        backendBundleSha256: manifest.review.backendBundleSha256,
      },
    };
    await claimJson(join(root, slotFile(slot, "claim")), claim);
    return claim;
  });
}

export async function admitPromptExecutionSlot(
  directory: string,
  slot: number,
  observationBytes: Uint8Array,
  now = Date.now(),
) {
  await assertOfflinePermissions();
  integer(slot, 1, 36);
  const root = resolve(directory);
  await privateDirectory(root);
  return await withRunLock(root, async () => {
    const { manifest, manifestSha256, read } = await readPromptExecution(root);
    check(
      !await exists(join(root, slotFile(slot, "completed"))) &&
        !await exists(join(root, slotFile(slot, "excluded"))),
    );
    const claim = fields(await read(slotFile(slot, "claim")), [
      "version",
      "manifestSha256",
      "slot",
      "block",
      "claimedAt",
      "privatePreflight",
      "activationSha256",
      "expected",
    ]);
    check(
      claim.version === "audio_prompt_execution_claim_v1" &&
        claim.manifestSha256 === manifestSha256 && claim.slot === slot,
    );
    const completed = await (async () => {
      try {
        const assignment = PLAN.assignments[slot - 1], block = assignment.block;
        check(
          claim.block === block &&
            !await exists(join(root, controlFile(block, "cleanup"))),
        );
        const activation = requirePromptControl(
          await read(controlFile(block, "activation")),
          manifest,
          block,
          "activation",
        );
        check(await fingerprintJson(activation) === claim.activationSha256);
        const expected = {
          slot,
          app: manifest.review.app,
          backendBundleSha256: manifest.review.backendBundleSha256,
        };
        check(
          await fingerprintJson(expected) ===
            await fingerprintJson(claim.expected),
        );
        check(
          observationBytes.length > 0 && observationBytes.length <= 1_048_576,
        );
        const lines = new TextDecoder("utf-8", { fatal: true }).decode(
          observationBytes,
        ).trimEnd().split("\n");
        check(
          lines.length <= 103 && lines.every((line) => line.length <= 16_384),
        );
        const rows = lines.map((line) => JSON.parse(line));
        const admitted = await admitAudioPromptComparisonWindow(rows, expected);
        check(
          await fingerprintJson(rows[0].pricing) ===
            await fingerprintJson(manifest.review.pricing),
        );
        const start = executionInstant(rows[0].startedAt),
          finish = executionInstant(rows.at(-1).finishedAt);
        const window = manifest.review.windows[block - 1];
        check(
          start >= executionInstant(claim.claimedAt) && finish <= now &&
            finish < executionInstant(window.expiresAt),
        );
        // Retain complete unfavorable results and missing-cost evidence. Missing
        // cost remains explicitly inconclusive for the eventual decision screen.
        return {
          version: "audio_prompt_execution_completion_v1",
          manifestSha256,
          slot,
          claimSha256: await fingerprintJson(claim),
          finishedAt: rows.at(-1).finishedAt,
          observationSha256: await fingerprintBytes(observationBytes),
          admittedSha256: await fingerprintJson(admitted),
          admitted,
        };
      } catch {
        await claimJson(join(root, slotFile(slot, "excluded")), {
          version: "audio_prompt_execution_exclusion_v1",
          manifestSha256,
          slot,
          claimSha256: await fingerprintJson(claim),
          excludedAt: new Date(now).toISOString(),
          reason: "observation_not_admitted",
          automaticSubmissions: 0,
        });
        throw new Error("audio_prompt_execution_observation_excluded");
      }
    })();
    await claimJson(join(root, slotFile(slot, "completed")), completed);
    return completed;
  });
}

/** Record verified cleanup even after an incomplete slot. It never clears the
 * claim or authorizes resuming it, and subsequent cleanup evidence is immutable. */
export async function closePromptExecutionBlock(
  directory: string,
  block: number,
  controlValue: unknown,
  now = Date.now(),
) {
  await assertOfflinePermissions();
  integer(block, 1, 3);
  const root = resolve(directory);
  await privateDirectory(root);
  return await withRunLock(root, async () => {
    const { manifest, read } = await readPromptExecution(root);
    const cleanup = requirePromptControl(
      controlValue,
      manifest,
      block,
      "cleanup",
    );
    const activation = requirePromptControl(
      await read(controlFile(block, "activation")),
      manifest,
      block,
      "activation",
    );
    let after = executionInstant(activation.observedAt);
    for (let slot = (block - 1) * 12 + 1; slot <= block * 12; slot++) {
      for (const kind of ["claim", "completed", "excluded"] as const) {
        if (await exists(join(root, slotFile(slot, kind)))) {
          const v = await read(slotFile(slot, kind)) as Record<string, unknown>;
          after = Math.max(
            after,
            executionInstant(
              v[
                kind === "claim"
                  ? "claimedAt"
                  : kind === "completed"
                  ? "finishedAt"
                  : "excludedAt"
              ],
            ),
          );
        }
      }
    }
    check(
      executionInstant(cleanup.observedAt) >= after &&
        executionInstant(cleanup.observedAt) <= now,
    );
    await claimJson(join(root, controlFile(block, "cleanup")), cleanup);
    return cleanup;
  });
}
