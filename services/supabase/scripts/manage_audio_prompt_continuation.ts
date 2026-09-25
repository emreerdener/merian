/** Offline amendment only. Never invokes a model, updates a secret or submits. */
import { resolve } from "node:path";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import {
  admitPromptContinuationSlot,
  claimPromptContinuationSlot,
  closePromptContinuationBlock,
  inspectPromptContinuationOriginal,
  preparePromptContinuation,
  promptContinuationRuntime,
  writePromptContinuationReport,
} from "./identification_evaluation/audioPromptContinuation.ts";
import { readJson } from "./identification_evaluation/files.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";

export async function manageAudioPromptContinuation(args: string[]) {
  await assertOfflinePermissions();
  const [operation, directory] = args;
  check(typeof directory === "string");
  const lengths: Record<string, number> = {
    inspect: 2,
    prepare: 3,
    claim: 5,
    admit: 3,
    close: 4,
    report: 3,
  };
  check(
    Object.hasOwn(lengths, operation) && args.length === lengths[operation],
  );
  const original = resolve(directory);
  if (operation === "inspect") {
    console.log(
      JSON.stringify(await inspectPromptContinuationOriginal(original)),
    );
    return;
  }
  if (operation === "prepare") {
    await preparePromptContinuation(
      original,
      await readJson(resolve(args[2]), 16_384),
    );
  } else if (operation === "report") {
    await writePromptContinuationReport(original, args[2]);
  } else {
    check(/^[1-9][0-9]?$/.test(args[2]));
    const index = Number(args[2]);
    if (operation === "claim") {
      await claimPromptContinuationSlot(
        original,
        index,
        await readJson(resolve(args[3]), 4096),
        {
          ...promptContinuationRuntime,
          privatePreflight: () => readJson(resolve(args[4]), 2048),
        },
      );
    } else if (operation === "admit") {
      await admitPromptContinuationSlot(original, index);
    } else {await closePromptContinuationBlock(
        original,
        index,
        await readJson(resolve(args[3]), 4096),
      );}
  }
  console.log(JSON.stringify({ status: operation, automaticSubmissions: 0 }));
}

if (import.meta.main) {
  try {
    await manageAudioPromptContinuation(Deno.args);
  } catch {
    console.error("audio_prompt_continuation_step_failed");
    Deno.exit(1);
  }
}
