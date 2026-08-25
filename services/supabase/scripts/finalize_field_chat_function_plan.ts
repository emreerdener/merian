import { REQUIRED_FIELD_CHAT_BUNDLES } from "./activate_field_chat_cutover.ts";

export type FieldChatCutoverPlanStatus = "pending" | "ready" | "active";

export interface FinalizedFunctionPlan {
  functions: string[];
  forcedFieldChatBundles: boolean;
}

const FUNCTION_NAME_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function finalizeFunctionPlanForFieldChatCutover(
  rawPlan: string,
  status: FieldChatCutoverPlanStatus,
): FinalizedFunctionPlan {
  if (status !== "pending" && status !== "ready" && status !== "active") {
    throw new Error(`Unexpected Field Chat cutover status: ${status}`);
  }
  const selected = new Set<string>();
  for (const rawName of rawPlan.split(/\r?\n/)) {
    const name = rawName.trim();
    if (!name) continue;
    if (!FUNCTION_NAME_PATTERN.test(name)) {
      throw new Error(`Invalid Edge Function name in deployment plan: ${name}`);
    }
    selected.add(name);
  }

  const forcedFieldChatBundles = status === "ready";
  if (forcedFieldChatBundles) {
    for (const functionName of REQUIRED_FIELD_CHAT_BUNDLES) {
      selected.add(functionName);
    }
  }
  return {
    functions: [...selected].sort(),
    forcedFieldChatBundles,
  };
}

function argumentValue(name: string): string | undefined {
  const index = Deno.args.indexOf(name);
  return index >= 0 ? Deno.args[index + 1] : undefined;
}

if (import.meta.main) {
  const inputPath = argumentValue("--input");
  const outputPath = argumentValue("--output");
  const status = argumentValue("--status") as
    | FieldChatCutoverPlanStatus
    | undefined;
  if (!inputPath || !outputPath || !status) {
    throw new Error("--input, --output, and --status are required");
  }
  const result = finalizeFunctionPlanForFieldChatCutover(
    await Deno.readTextFile(inputPath),
    status,
  );
  const rendered = result.functions.length === 0
    ? ""
    : `${result.functions.join("\n")}\n`;
  await Deno.writeTextFile(outputPath, rendered);
  console.log(result.forcedFieldChatBundles ? "forced" : "unchanged");
}
