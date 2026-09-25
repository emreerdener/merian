/** Read-only bindings for both closed predecessors. Call under their locks. */
import { dirname, join, resolve } from "node:path";
import { executionInstant } from "./audioPromptExecution.ts";
import {
  continuationLedger,
  promptContinuationDirectory,
  type PromptContinuationRuntime,
  readPromptContinuation,
} from "./audioPromptContinuation.ts";
import {
  auditOriginalPromptExecution,
  promptEvidenceFiles,
  promptSlotFile,
  samePromptValue,
  withOriginalPromptLock,
} from "./audioPromptExecutionEvidence.ts";
import { readPromptLedgerState } from "./audioPromptLedger.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import {
  containedPath,
  exists,
  privateDirectory,
  readBytes,
  readJson,
} from "./files.ts";
import { integer, requireCondition as check } from "./validation.ts";

export const promptSuccessorDirectory = (original: string) =>
  promptContinuationDirectory(original) + ".successor";

/** The original lock is always first; neither existing inode is created/written. */
export function withPromptSuccessorParents<T>(
  directory: string,
  work: (original: string, continuation: string) => Promise<T>,
) {
  return withOriginalPromptLock(
    directory,
    (original) =>
      withOriginalPromptLock(
        promptContinuationDirectory(original),
        (continuation) => work(original, continuation),
      ),
  );
}

export interface RetainedPromptReport {
  path: string;
  sha256: string;
}
export interface PromptReportPaths {
  original: string;
  continuation: string;
}

async function reportBinding(path: string): Promise<RetainedPromptReport> {
  check(typeof path === "string" && path.endsWith(".json"));
  check(path === resolve(path) && await Deno.realPath(path) === path);
  await privateDirectory(dirname(path));
  const stat = await Deno.lstat(path);
  check(stat.mode !== null && (stat.mode & 0o077) === 0);
  const bytes = await readBytes(path, 8_388_608);
  // Historical reports are opaque, bounded JSON artifacts. Their contents never
  // substitute for re-admission of observations and are not emitted.
  JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  return { path, sha256: await fingerprintBytes(bytes) };
}

export async function auditPromptSuccessorParents(
  original: string,
  continuation: string,
  reports: PromptReportPaths,
  now: number,
  runtime: PromptContinuationRuntime,
) {
  check(continuation === promptContinuationDirectory(original));
  const originalAudit = await auditOriginalPromptExecution(
    original,
    now,
    runtime,
  );
  const context = await readPromptContinuation(continuation);
  check(
    await samePromptValue(context.manifest.original, originalAudit.binding),
  );
  const state = await readPromptLedgerState(
    continuation,
    continuationLedger(context),
    now,
  );
  check(state.pending === null && state.rows.length > 0);
  const completedThrough = originalAudit.binding.completedThrough +
    state.rows.length;
  integer(completedThrough, 2, 35);
  check(completedThrough % 12 !== 0);
  const lastBlock = Math.ceil(completedThrough / 12);
  check(
    state.controls.length > 0 &&
      state.controls.every((c) => c.cleanup !== null),
  );
  check(state.controls.at(-1)!.block === lastBlock);
  const lastCleanupAt = state.controls.at(-1)!.cleanup!.observedAt as string;
  const expiredAt =
    context.manifest.review.windows.find((w) => w.block === lastBlock)!
      .expiresAt;
  check(executionInstant(lastCleanupAt) >= executionInstant(expiredAt));
  check(
    executionInstant(state.previousFinishedAt) < executionInstant(expiredAt),
  );
  const allowed = new Set([
    ".lock",
    "run.json",
    "freeze.json",
    "slots",
    "controls",
    "observations",
    "operator",
    "witnesses",
  ]);
  for await (const entry of Deno.readDir(continuation)) {
    check(allowed.has(entry.name) && !entry.isSymlink);
  }
  const paths = ["run.json", "freeze.json"];
  for (
    const directory of [
      "slots",
      "controls",
      "observations",
      "operator",
      "witnesses",
    ]
  ) {
    if (!await exists(join(continuation, directory))) continue;
    for (const name of await promptEvidenceFiles(continuation, directory)) {
      if (directory === "operator" || directory === "witnesses") {
        const match = /^slot-([0-9]{2})(\.preparation-note)?\.json$/.exec(name);
        check(match !== null);
        integer(Number(match[1]), context.manifest.firstSlot, completedThrough);
        if (directory === "witnesses") {
          check(match[2] === undefined);
          const claim = await context.read(
            promptSlotFile(Number(match[1]), "claim"),
          ) as { privatePreflight: unknown };
          check(
            await samePromptValue(
              await readJson(
                await containedPath(continuation, directory + "/" + name),
                16_384,
              ),
              claim.privatePreflight,
            ),
          );
        }
      }
      paths.push(directory + "/" + name);
    }
  }
  const files = [];
  for (const path of paths.sort()) {
    const full = await containedPath(continuation, path);
    const stat = await Deno.lstat(full);
    check(stat.mode !== null && (stat.mode & 0o077) === 0);
    files.push({
      path,
      sha256: await fingerprintBytes(
        await readBytes(
          full,
          path.startsWith("observations/") ? 1_048_576 : 262_144,
        ),
      ),
    });
  }
  check(reports.original !== reports.continuation);
  const retainedReports = {
    original: await reportBinding(reports.original),
    continuation: await reportBinding(reports.continuation),
  };
  const binding = {
    originalDirectory: original,
    continuationDirectory: continuation,
    original: originalAudit.binding,
    continuation: {
      manifestSha256: context.manifestSha256,
      manifestFileSha256: await fingerprintBytes(
        await readBytes(await containedPath(continuation, "run.json"), 262_144),
      ),
      evidenceSha256: await fingerprintJson(files),
      completedThrough,
      lastCompletedAt: state.previousFinishedAt,
      lastCleanupAt,
      expiredAt,
    },
    reports: retainedReports,
  };
  return {
    binding: { ...binding, evidenceSha256: await fingerprintJson(binding) },
    originalRows: originalAudit.rows,
    continuationRows: state.rows,
    originalControls: originalAudit.controls,
    continuationControls: state.controls,
    files,
  };
}
export type PromptSuccessorBinding = Awaited<
  ReturnType<typeof auditPromptSuccessorParents>
>["binding"];

/** Public evidence projections omit private path locators used by the ledger. */
export function promptSuccessorBindingSummary(binding: PromptSuccessorBinding) {
  return {
    original: binding.original,
    continuation: binding.continuation,
    retainedReports: {
      originalSha256: binding.reports.original.sha256,
      continuationSha256: binding.reports.continuation.sha256,
    },
    evidenceSha256: binding.evidenceSha256,
  };
}
