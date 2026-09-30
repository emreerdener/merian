/** Explicit local assessment entry point; historical evaluator contracts stay frozen. */
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { createOpenAIConfidenceEvaluationAdapter } from "../functions/_shared/ai/openai.ts";
import {
  assertOfflinePermissions,
  liveCredential,
} from "./identification_evaluation/admission.ts";
import {
  atomicJson,
  exists,
  privateDirectory,
  readJson,
  sourceIdentity,
  withRunLock,
} from "./identification_evaluation/files.ts";
import {
  type ConfidenceCorpus,
  parseConfidenceCorpus,
} from "./identification_evaluation/confidenceCorpus.ts";
import { assignConfidenceSplits } from "./identification_evaluation/confidenceSampling.ts";
import { prepareConfidenceStudy } from "./identification_evaluation/confidencePreparation.ts";
import {
  executeConfidenceStudy,
  saveConfidenceReport,
} from "./identification_evaluation/confidenceRunner.ts";
import {
  member,
  requireCondition as check,
} from "./identification_evaluation/validation.ts";

export async function main(args = Deno.args) {
  check(args.length === 2);
  const [mode, path] = args;
  member(mode, ["assign-splits", "prepare", "report", "--live"]);
  if (mode !== "--live") await assertOfflinePermissions();
  const repository = fileURLToPath(new URL("../../../", import.meta.url));
  const root = await privateDirectory(path);
  check(relative(await Deno.realPath(repository), root).startsWith("../"));
  if (mode === "assign-splits") {
    return await withRunLock(root, async () => {
      check(
        !await exists(join(root, "confidence-manifest.json")) &&
          !await exists(join(root, "confidence-attempts")),
      );
      const path = join(root, "confidence-corpus.json");
      const raw = await readJson(path) as ConfidenceCorpus;
      const { corpus } = parseConfidenceCorpus({
        ...raw,
        cases: assignConfidenceSplits(raw.cases),
      }, await readJson(join(root, "taxonomy.json")));
      await atomicJson(path, corpus);
    });
  }
  const source = await sourceIdentity(repository);
  if (mode === "--live") {
    await executeConfidenceStudy(
      root,
      source,
      "live",
      createOpenAIConfidenceEvaluationAdapter(await liveCredential("openai")),
    );
  } else {await withRunLock(root, async () => {
      const study = await prepareConfidenceStudy(root, source);
      if (mode === "prepare") {
        await atomicJson(join(root, "confidence-readiness.json"), {
          version: "openai_confidence_readiness_v1",
          manifestDigest: study.digest,
          scheduled: study.corpus.cases.length,
          dispatchAuthorized: false,
          referenceStatus: study.corpus.referenceStatus,
          mode: study.manifest.mode,
          initialReservationWithinBudget:
            study.manifest.assignments[0].reservationNanoUsd <= 10_000_000_000,
        });
      }
      await saveConfidenceReport(root, study);
    });}
}
if (import.meta.main) {
  try {
    await main();
    console.log(
      "Confidence assessment artifacts written; review the private report.",
    );
  } catch {
    console.error("openai_confidence_assessment_stopped");
    Deno.exitCode = 1;
  }
}
