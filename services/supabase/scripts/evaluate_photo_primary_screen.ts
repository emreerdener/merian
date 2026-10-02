/** Separate screen; offline by default, one durable slot per --one-live invocation. */
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import {
  exists,
  privateDirectory,
  sourceIdentity,
  withRunLock,
} from "./identification_evaluation/files.ts";
import {
  preparePrimaryScreen,
  type PrimaryScreenArm,
} from "./identification_evaluation/photoPrimaryScreenPreparation.ts";
import {
  dispatchPrimaryScreen,
  primaryScreenReport,
} from "./identification_evaluation/photoPrimaryScreenRunner.ts";
import {
  member,
  requireCondition as check,
} from "./identification_evaluation/validation.ts";
export async function main(args = Deno.args) {
  check(args.length === 2 || args.length === 3);
  const [mode, path, arm] = args;
  member(mode, ["prepare", "report", "next", "--one-live"]);
  check((mode === "--one-live") === (args.length === 3));
  if (mode !== "--one-live") await assertOfflinePermissions();
  const repository = fileURLToPath(new URL("../../../", import.meta.url));
  const root = await privateDirectory(path);
  check(relative(await Deno.realPath(repository), root).startsWith("../"));
  await withRunLock(root, async () => {
    if (mode !== "prepare") {
      check(await exists(join(root, "screen-manifest.json")));
    }
    const study = await preparePrimaryScreen(
      root,
      await sourceIdentity(repository),
    );
    if (mode === "--one-live") {
      member(arm, ["released", "primary"]);
      await dispatchPrimaryScreen(root, study, arm as PrimaryScreenArm);
    }
    const r = await primaryScreenReport(root, study);
    console.log(
      mode === "next"
        ? r.report.stop ? "blocked" : r.next?.arm ?? "complete"
        : JSON.stringify({
          attempted: r.report.attempted,
          settledNanoUsd: r.report.settledNanoUsd,
          outstandingNanoUsd: r.report.outstandingNanoUsd,
          complete: r.report.complete,
          stop: r.report.stop,
        }),
    );
  });
}
if (import.meta.main) {
  try {
    await main();
  } catch {
    console.error("photo_primary_screen_stopped");
    Deno.exitCode = 1;
  }
}
