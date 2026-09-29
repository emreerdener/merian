/** Separate explicit-primary evaluator. No import-time execution. */
import { fileURLToPath } from "node:url";
import { relative } from "node:path";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import {
  privateDirectory,
  sourceIdentity,
} from "./identification_evaluation/files.ts";
import { prepareSolPrimaryComparison } from "./identification_evaluation/solPhotoPrimaryLivePreparation.ts";
import { executeSolPrimaryComparison } from "./identification_evaluation/solPhotoPrimaryRunner.ts";
import { requireCondition as check } from "./identification_evaluation/validation.ts";

export async function main(args = Deno.args) {
  check(args.length === 2 && ["preflight", "--live"].includes(args[0]));
  if (args[0] !== "--live") await assertOfflinePermissions();
  const repository = fileURLToPath(new URL("../../../", import.meta.url));
  const path = await Deno.realPath(args[1]);
  const rel = relative(await Deno.realPath(repository), path);
  check(rel === ".." || rel.startsWith("../"));
  const root = await privateDirectory(path);
  const source = await sourceIdentity(repository);
  const result = args[0] === "preflight"
    ? await prepareSolPrimaryComparison(root, source)
    : await executeSolPrimaryComparison(root, source, "live");
  console.log("sol_primary_evaluation_artifacts_written");
  return result;
}
if (import.meta.main) {
  try {
    await main();
  } catch {
    console.error("sol_primary_evaluation_failed_closed");
    Deno.exitCode = 1;
  }
}
