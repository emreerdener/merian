/** Offline ledger only. Neither a claim nor a freeze submits an identification. */
import { resolve } from "node:path";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import {
  admitPromptExecutionSlot,
  claimPromptExecutionSlot,
  closePromptExecutionBlock,
  promptExecutionRuntime,
} from "./identification_evaluation/audioPromptExecution.ts";
import { readBytes, readJson } from "./identification_evaluation/files.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";

export async function manageAudioPromptExecution(args: string[]) {
  await assertOfflinePermissions();
  check(
    args.length === (args[0] === "claim" ? 5 : 4) &&
      ["claim", "admit", "close"].includes(args[0]),
  );
  check(/^[1-9][0-9]?$/.test(args[2]));
  const [operation, directory, index, input] = args;
  if (operation === "claim") {
    await claimPromptExecutionSlot(
      resolve(directory),
      Number(index),
      await readJson(resolve(input), 4096),
      {
        ...promptExecutionRuntime,
        privatePreflight: () => readJson(resolve(args[4]), 2048),
      },
    );
  } else if (operation === "close") {
    await closePromptExecutionBlock(
      resolve(directory),
      Number(index),
      await readJson(resolve(input), 4096),
    );
  } else {
    await admitPromptExecutionSlot(
      resolve(directory),
      Number(index),
      await readBytes(resolve(input), 1_048_576),
    );
  }
  console.log(
    JSON.stringify({
      status: operation,
      index: Number(index),
      automaticSubmissions: 0,
    }),
  );
}
if (import.meta.main) {
  try {
    await manageAudioPromptExecution(Deno.args);
  } catch {
    console.error("audio_prompt_execution_step_failed");
    Deno.exit(1);
  }
}
