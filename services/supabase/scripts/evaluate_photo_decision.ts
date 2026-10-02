/** Authorized study only. Default modes are offline; --one-live consumes one slot. */
import { relative } from "node:path";
import { fileURLToPath } from "node:url";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import {
  exists,
  privateDirectory,
  sourceIdentity,
  withRunLock,
} from "./identification_evaluation/files.ts";
import {
  type DecisionArm,
  preparePhotoDecision,
} from "./identification_evaluation/photoDecisionPreparation.ts";
import {
  dispatchPhotoDecision,
  freezePhotoValidation,
  photoDecisionReport,
} from "./identification_evaluation/photoDecisionRunner.ts";
import {
  member,
  requireCondition as check,
} from "./identification_evaluation/validation.ts";
import { join } from "node:path";

export async function main(args = Deno.args) {
  check(args.length === 2 || args.length === 3);
  const [mode, path, arm] = args;
  member(mode, ["prepare", "report", "next", "select", "--one-live"]);
  check((mode === "--one-live") === (args.length === 3));
  if (mode !== "--one-live") await assertOfflinePermissions();
  const repository = fileURLToPath(new URL("../../../", import.meta.url));
  const root = await privateDirectory(path);
  check(relative(await Deno.realPath(repository), root).startsWith("../"));
  await withRunLock(root, async () => {
    if (mode !== "prepare") {
      check(await exists(join(root, "decision-manifest.json")));
    }
    const study = await preparePhotoDecision(
      root,
      await sourceIdentity(repository),
    );
    if (mode === "select") await freezePhotoValidation(root, study);
    if (mode === "--one-live") {
      member(arm, ["released", "gemini", "evidence"]);
      await dispatchPhotoDecision(root, study, arm as DecisionArm);
    }
    const result = await photoDecisionReport(root, study);
    if (mode === "next") {
      console.log(
        result.report.stop
          ? "blocked"
          : result.selectionNeeded
          ? "select"
          : result.next?.arm ?? "complete",
      );
    } else {console.log(JSON.stringify({
        attempted: result.report.attempted,
        settledNanoUsd: result.report.settledNanoUsd,
        outstandingNanoUsd: result.report.outstandingNanoUsd,
        stop: result.report.stop,
        complete: result.report.complete,
      }));}
  });
}
if (import.meta.main) {
  try {
    await main();
  } catch {
    console.error("photo_decision_stopped");
    Deno.exitCode = 1;
  }
}
