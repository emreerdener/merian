import { preparePhotoModelContinuation } from "./identification_evaluation/photoModelContinuation.ts";
import {
  executePhotoModelComparison,
  executePhotoModelContinuation,
} from "./identification_evaluation/photoModelRunner.ts";
import { preparePhotoModelComparison } from "./identification_evaluation/photoModelPreparation.ts";
import { createNullFieldsDemo } from "./identification_evaluation/nullFieldsOffline.ts";
import { createCandidateDemo } from "./identification_evaluation/candidateOffline.ts";
import { calibrateReviewer } from "./identification_evaluation/explanationReview.ts";
import { CALIBRATION_EXAMPLES } from "./identification_evaluation/explanationCalibration.ts";
import { saveExperimentReport } from "./identification_evaluation/experimentReport.ts";
import {
  executeExperimentRun,
  prepareExperiment,
} from "./identification_evaluation/experiment.ts";
import {
  createExperimentDemo,
  experimentOfflineOutcome,
} from "./identification_evaluation/experimentOffline.ts";
import { compareExploratoryRuns } from "./identification_evaluation/exploratoryComparison.ts";
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
  withRunLock,
} from "./identification_evaluation/files.ts";
import {
  createDemo,
  createMeasurementDemo,
  createProviderDemo,
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
    "demo-experiment",
    "demo-candidate",
    "demo-null-fields",
    "calibrate-explanations",
    "experiment-preflight",
    "experiment-report",
    "experiment-offline",
    "--experiment-live",
    "demo-exploratory",
    "demo-providers",
    "demo-measurement",
    "preflight",
    "preflight-free-pro-photo",
    "preflight-free-pro-photo-continuation",
    "--photo-model-live",
    "--photo-model-continuation-live",
    "offline",
    "--live",
    "report",
    "compare",
    "compare-exploratory",
  ];
  const mode = known.includes(args[0]) ? args[0] : "offline";
  const values = known.includes(args[0]) ? args.slice(1) : args;
  check(
    values.length ===
      ((mode === "compare" || mode === "compare-exploratory") ? 5 : [
          "report",
          "experiment-offline",
          "--experiment-live",
          "calibrate-explanations",
        ].includes(mode)
        ? 2
        : 1),
  );
  if (
    mode !== "--live" && mode !== "--experiment-live" &&
    mode !== "calibrate-explanations" && mode !== "--photo-model-live" &&
    mode !== "--photo-model-continuation-live"
  ) {
    await assertOfflinePermissions();
  }
  const repository = fileURLToPath(new URL("../../../", import.meta.url));
  if (
    mode === "demo" || mode === "demo-exploratory" ||
    mode === "demo-providers" || mode === "demo-measurement" ||
    mode === "demo-experiment" || mode === "demo-candidate" ||
    mode === "demo-null-fields"
  ) {
    check(!await exists(values[0]));
  }
  const root = await privateDirectory(values[0]);
  const rel = relative(await Deno.realPath(repository), root);
  check(rel.startsWith("../")); // All corpus/artifacts, even examples, outside Git.
  if (mode === "demo") await createDemo(root);
  if (mode === "demo-exploratory") await createDemo(root, true);
  if (mode === "demo-providers") await createProviderDemo(root);
  if (mode === "demo-measurement") await createMeasurementDemo(root);
  const save = async (runId: string) =>
    parseRunCorpus(await readJson(join(root, "corpus.json"))).kind ===
        "exploratory"
      ? await saveExploratoryReport(root, runId)
      : await saveReport(root, runId);
  if (mode === "--photo-model-continuation-live") {
    await executePhotoModelContinuation(
      root,
      await sourceIdentity(repository),
      "live",
    );
  } else if (mode === "preflight-free-pro-photo-continuation") {
    await preparePhotoModelContinuation(root, await sourceIdentity(repository));
  } else if (mode === "--photo-model-live") {
    await executePhotoModelComparison(
      root,
      await sourceIdentity(repository),
      "live",
    );
  } else if (mode === "preflight-free-pro-photo") {
    await preparePhotoModelComparison(root, await sourceIdentity(repository));
  } else if (mode === "calibrate-explanations") {
    await calibrateReviewer(root, values[1]);
  } else if (mode === "experiment-report") {
    await saveExperimentReport(root);
  } else if (
    mode === "demo-experiment" || mode === "demo-candidate" ||
    mode === "demo-null-fields" ||
    mode === "experiment-preflight" ||
    mode === "experiment-offline" || mode === "--experiment-live"
  ) {
    const source = await sourceIdentity(repository);
    if (mode === "demo-experiment") await createExperimentDemo(root, source);
    if (mode === "demo-candidate") await createCandidateDemo(root, source);
    if (mode === "demo-null-fields") await createNullFieldsDemo(root, source);
    const prepared = await prepareExperiment(root, source);
    check(mode !== "--experiment-live" || prepared.plan.mode === "live");
    if (
      mode === "experiment-offline" || mode === "demo-experiment" ||
      mode === "demo-candidate" || mode === "demo-null-fields"
    ) {
      check(prepared.plan.mode === "offline");
    }
    if (mode === "experiment-preflight") {
      await atomicJson(join(root, "experiment-preflight.json"), {
        version: "identification_experiment_preflight_v1",
        dispatchAuthorized: false,
        planDigest: prepared.digest,
        profiles: prepared.profiles,
        plannedCalls: prepared.plan.runs.reduce((n, r) => n + r.maxCalls, 0),
        allocatedUsd: prepared.plan.runs.reduce((n, r) => n + r.budgetUsd, 0),
      });
    } else {
      const selected =
        (mode === "demo-experiment" || mode === "demo-candidate" ||
            mode === "demo-null-fields")
          ? prepared.plan.runs.map((r) => r.runId)
          : [values[1]];
      for (const runId of selected) {
        const index = prepared.plan.runs.findIndex((r) => r.runId === runId);
        check(index >= 0);
        const dependencies = mode === "--experiment-live" ? {} : {
          ...(prepared.plan.review
            ? {
              review: () =>
                Promise.resolve(
                  structuredClone(CALIBRATION_EXAMPLES[0].expected),
                ),
            }
            : {}),
          offlineOutcome: await experimentOfflineOutcome(
            root,
            prepared.inputs[index],
          ),
        };
        const state = await executeExperimentRun(
          root,
          runId,
          source,
          dependencies,
        );
        await save(runId);
        if (state.stop) break;
      }
      if (mode !== "--experiment-live") await saveExperimentReport(root);
    }
  } else if (mode === "preflight") {
    await preflightCorpus(root, await sourceIdentity(repository));
  } else if (mode === "report") {
    token(values[1]);
    await save(values[1]);
  } else if (mode === "compare-exploratory") {
    const [, leftId, rightId, leftProfile, rightProfile] = values;
    token(leftId);
    token(rightId);
    member(leftProfile, PROFILES);
    member(rightProfile, PROFILES);
    const load = async (runId: string) => {
      const directory = join(root, "runs", runId);
      return await withRunLock(directory, async () => {
        const manifest = parseManifest(
          await readJson(join(directory, "manifest.json")),
        );
        check(manifest.spec.runId === runId);
        return { manifest, records: await readRecords(directory, manifest) };
      });
    };
    const left = await load(leftId),
      right = leftId === rightId ? left : await load(rightId);
    const comparison = await compareExploratoryRuns(
      await readJson(join(root, "corpus.json")),
      await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
      left.manifest,
      left.records,
      right.manifest,
      right.records,
      { leftProfile, rightProfile },
    );
    await atomicJson(
      join(
        root,
        `comparison-exploratory-${leftId}-${rightId}-${leftProfile}-${rightProfile}.json`,
      ),
      comparison,
    );
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
