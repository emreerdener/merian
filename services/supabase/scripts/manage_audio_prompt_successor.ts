/** Offline amendment only. Never invokes a model, updates a secret or submits. */
import { resolve } from "node:path";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import {
  admitPromptSuccessorSlot,
  claimPromptSuccessorSlot,
  closePromptSuccessorBlock,
  inspectPromptSuccessor,
  preparePromptSuccessor,
  writePromptSuccessorReport,
} from "./identification_evaluation/audioPromptSuccessor.ts";
import { promptContinuationRuntime } from "./identification_evaluation/audioPromptContinuation.ts";
import { readJson } from "./identification_evaluation/files.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";

export async function manageAudioPromptSuccessor(args: string[]) {
  await assertOfflinePermissions();
  const [operation, directory] = args;
  check(typeof directory === "string");
  const lengths: Record<string, number> = {
    inspect: 4,
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
      JSON.stringify(
        await inspectPromptSuccessor(original, {
          original: resolve(args[2]),
          continuation: resolve(args[3]),
        }),
      ),
    );
    return;
  }
  if (operation === "prepare") {
    await preparePromptSuccessor(
      original,
      await readJson(resolve(args[2]), 16_384),
    );
  } else if (operation === "report") {
    await writePromptSuccessorReport(original, args[2]);
  } else {
    check(/^[1-9][0-9]?$/.test(args[2]));
    const index = Number(args[2]);
    if (operation === "claim") {
      await claimPromptSuccessorSlot(
        original,
        index,
        await readJson(resolve(args[3]), 4096),
        {
          ...promptContinuationRuntime,
          privatePreflight: () => readJson(resolve(args[4]), 2048),
        },
      );
    } else if (operation === "admit") {
      await admitPromptSuccessorSlot(original, index);
    } else {await closePromptSuccessorBlock(
        original,
        index,
        await readJson(resolve(args[3]), 4096),
      );}
  }
  console.log(JSON.stringify({ status: operation, automaticSubmissions: 0 }));
}

if (import.meta.main) {
  try {
    await manageAudioPromptSuccessor(Deno.args);
  } catch {
    console.error("audio_prompt_successor_step_failed");
    Deno.exit(1);
  }
}
