/** Owner-approved local 12-call comparison. Never changes production assignment. */
import { relative } from "node:path";
import { fileURLToPath } from "node:url";
import { createOpenAIPhotoReasoningEvaluationAdapter } from "../functions/_shared/ai/openai.ts";
import {
  assertOfflinePermissions,
  liveCredential,
} from "./identification_evaluation/admission.ts";
import {
  privateDirectory,
  sourceIdentity,
  withRunLock,
} from "./identification_evaluation/files.ts";
import {
  executeReasoningPilot,
  prepareReasoningPilot,
  saveReasoningReport,
} from "./identification_evaluation/reasoningPilot.ts";
import { assertPrivateReviewReady } from "./identification_evaluation/explanationView.ts";
import { reviewExplanation } from "./identification_evaluation/explanationReview.ts";
import {
  member,
  requireCondition as check,
} from "./identification_evaluation/validation.ts";

export async function main(args = Deno.args) {
  check(args.length === 2);
  const [mode, path] = args;
  member(mode, ["prepare", "report", "--live"]);
  if (mode !== "--live") await assertOfflinePermissions();
  const repository = fileURLToPath(new URL("../../../", import.meta.url));
  const root = await privateDirectory(path);
  check(relative(await Deno.realPath(repository), root).startsWith("../"));
  const source = await sourceIdentity(repository);
  if (mode === "--live") {
    await assertPrivateReviewReady();
    await executeReasoningPilot(
      root,
      source,
      "live",
      createOpenAIPhotoReasoningEvaluationAdapter(
        await liveCredential("openai"),
      ),
      (display) => reviewExplanation(display, 600000, true),
    );
  } else {
    await withRunLock(root, async () => {
      await saveReasoningReport(
        root,
        await prepareReasoningPilot(root, source),
      );
    });
  }
}
if (import.meta.main) {
  try {
    await main();
    console.log(
      "Reasoning comparison artifacts written. Review the private report.",
    );
  } catch {
    console.error("openai_reasoning_comparison_stopped");
    Deno.exitCode = 1;
  }
}
