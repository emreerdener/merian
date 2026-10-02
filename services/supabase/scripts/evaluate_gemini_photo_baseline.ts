/** Local Gemini comparison only; no production mutation or OpenAI dispatch. */
import { relative } from "node:path";
import { fileURLToPath } from "node:url";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import {
  privateDirectory,
  sourceIdentity,
  withRunLock,
} from "./identification_evaluation/files.ts";
import {
  executeGeminiBaseline,
  prepareGeminiBaseline,
  saveGeminiBaseline,
} from "./identification_evaluation/geminiPhotoBaselinePilot.ts";
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
  if (mode === "--live") await executeGeminiBaseline(root, source, "live");
  else {await withRunLock(root, async () => {
      await saveGeminiBaseline(root, await prepareGeminiBaseline(root, source));
    });}
}
if (import.meta.main) {
  try {
    await main();
    console.log(
      "Gemini comparison artifacts written. Review the private report.",
    );
  } catch {
    console.error("gemini_photo_baseline_stopped");
    Deno.exitCode = 1;
  }
}
