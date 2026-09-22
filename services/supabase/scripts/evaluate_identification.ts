/** Local-only evaluator. Importing it performs no I/O and never dispatches. */
import { fileURLToPath } from "node:url";
import { join, relative } from "node:path";
import { assertOfflinePermissions } from "./identification_evaluation/admission.ts";
import { parseRunCorpus } from "./identification_evaluation/exploratory.ts";
import { saveExploratoryReport } from "./identification_evaluation/exploratoryReport.ts";
import { preflightCorpus } from "./identification_evaluation/preflight.ts";
import {
  atomicJson,
  exists,
  privateDirectory,
  readJson,
  sourceIdentity,
} from "./identification_evaluation/files.ts";
import {
  createDemo,
  offlineOutcomes,
} from "./identification_evaluation/offline.ts";
import {
  compareRuns,
  saveReport,
} from "./identification_evaluation/reports.ts";
import {
  parseManifest,
  PROFILES,
} from "./identification_evaluation/runContracts.ts";
import {
  executeRun,
  prepareRun,
  readRecords,
} from "./identification_evaluation/runner.ts";
import {
  member,
  parseEvaluationCorpus,
  requireCondition as check,
  token,
} from "./identification_evaluation/validation.ts";

export async function main(args = Deno.args): Promise<void> {
  const known = [
    "demo",
    "demo-exploratory",
    "preflight",
    "offline",
    "--live",
    "report",
    "compare",
  ];
  const mode = known.includes(args[0]) ? args[0] : "offline";
  const values = known.includes(args[0]) ? args.slice(1) : args;
  check(values.length === (mode === "compare" ? 5 : mode === "report" ? 2 : 1));
  if (mode !== "--live") await assertOfflinePermissions();
  const repository = fileURLToPath(new URL("../../../", import.meta.url));
  if (mode === "demo" || mode === "demo-exploratory") {
    check(!await exists(values[0]));
  }
  const root = await privateDirectory(values[0]);
  const rel = relative(await Deno.realPath(repository), root);
  check(rel.startsWith("../")); // All corpus/artifacts, even examples, outside Git.
  if (mode === "demo") await createDemo(root);
  if (mode === "demo-exploratory") await createDemo(root, true);
  const save = async (runId: string) =>
    parseRunCorpus(await readJson(join(root, "corpus.json"))).kind ===
        "exploratory"
      ? await saveExploratoryReport(root, runId)
      : await saveReport(root, runId);
  if (mode === "preflight") {
    await preflightCorpus(root, await sourceIdentity(repository));
  } else if (mode === "report") {
    token(values[1]);
    await save(values[1]);
  } else if (mode === "compare") {
    const [, leftId, rightId, leftProfile, rightProfile] = values;
    token(leftId);
    token(rightId);
    member(leftProfile, PROFILES);
    member(rightProfile, PROFILES);
    const leftDir = join(root, "runs", leftId),
      rightDir = join(root, "runs", rightId);
    const left = parseManifest(await readJson(join(leftDir, "manifest.json"))),
      right = parseManifest(await readJson(join(rightDir, "manifest.json")));
    const comparison = await compareRuns(
      parseEvaluationCorpus(await readJson(join(root, "corpus.json"))),
      await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
      left,
      await readRecords(leftDir, left),
      right,
      await readRecords(rightDir, right),
      {
        leftProfile,
        rightProfile,
        allowProfileDifference: leftProfile !== rightProfile,
      },
    );
    await atomicJson(
      join(root, `comparison-${leftId}-${rightId}.json`),
      comparison,
    );
  } else {
    const inputs = await prepareRun(
      root,
      await sourceIdentity(repository),
      mode === "--live" ? "live" : "offline",
    );
    const dependencies = mode === "--live" ? {} : {
      offlineOutcome: offlineOutcomes(
        await readJson(join(root, "fixtures.json")),
        inputs.corpus,
        inputs.manifest.spec,
      ),
    };
    await executeRun(root, inputs, dependencies);
    await save(inputs.manifest.spec.runId);
  }
  console.log("identification_evaluation_artifacts_written");
}
if (import.meta.main) {
  try {
    await main();
  } catch {
    // Do not print exception messages, paths, raw inputs or provider responses.
    console.error("identification_evaluation_failed_closed");
    Deno.exitCode = 1;
  }
}
