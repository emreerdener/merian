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
  prepareReasoningTradeoff,
  type TradeoffArm,
} from "./identification_evaluation/reasoningTradeoffPreparation.ts";
import {
  dispatchReasoningTradeoff,
  reasoningTradeoffReport,
} from "./identification_evaluation/reasoningTradeoffRunner.ts";
import {
  member,
  requireCondition as check,
} from "./identification_evaluation/validation.ts";
import { join } from "node:path";

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
      check(await exists(join(root, "tradeoff-manifest.json")));
    }
    const study = await prepareReasoningTradeoff(
      root,
      await sourceIdentity(repository),
    );
    if (mode === "--one-live") {
      member(arm, ["low", "medium", "gemini"]);
      await dispatchReasoningTradeoff(root, study, arm as TradeoffArm);
    }
    const result = await reasoningTradeoffReport(root, study);
    if (mode === "next") {
      console.log(
        result.report.stop ? "blocked" : result.next?.arm ?? "complete",
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
    console.error("reasoning_tradeoff_stopped");
    Deno.exitCode = 1;
  }
}
