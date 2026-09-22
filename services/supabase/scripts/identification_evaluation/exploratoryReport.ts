import { join } from "node:path";
import {
  INPUT_GROUPS,
  OUTCOMES,
  type Prediction,
  type Profile,
} from "./contracts.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  type ExploratoryCorpus,
  parseExploratoryCorpus,
} from "./exploratory.ts";
import { atomicJson, atomicText, readJson, withRunLock } from "./files.ts";
import { confidencePolicy } from "./profiles.ts";
import { performance, validateReportInputs } from "./reports.ts";
import { parseManifest } from "./runContracts.ts";
import { readRecords } from "./runner.ts";
import { assessReference, rate } from "./scoring.ts";
import { parsePrediction, requireCondition as check } from "./validation.ts";

/** All-case operational counts; only explicit provisional labels enter agreement. */
export function exploratoryAgreement(
  corpusValue: ExploratoryCorpus,
  predictionValues: Prediction[],
  profile: Profile,
) {
  const corpus = parseExploratoryCorpus(corpusValue);
  const predictions = predictionValues.map(parsePrediction);
  check(new Set(predictions.map((p) => p.caseId)).size === predictions.length);
  check(
    predictions.every((p) =>
      corpus.cases.some((c) => c.input.caseId === p.caseId)
    ),
  );
  const rows = corpus.cases.map((c) => {
    const prediction = predictions.find((p) => p.caseId === c.input.caseId) ??
      { caseId: c.input.caseId, outcome: "unattempted" as const };
    return {
      c,
      prediction,
      assessment: c.provisionalReference === null
        ? null
        : assessReference(c.provisionalReference, prediction),
    };
  });
  const labelled = rows.filter((r) => r.assessment !== null);
  const named = labelled.filter((r) => r.assessment!.named);
  const species = labelled.filter((r) =>
    r.c.provisionalReference!.supportedRank === "species"
  );
  const unresolved = labelled.filter((r) =>
    r.c.provisionalReference!.resolution === "unresolved"
  );
  const strong = named.filter((r) =>
    r.assessment!.score! >= confidencePolicy(profile).strong
  );
  return {
    evidenceStatus: corpus.evidenceOrigin === "synthetic"
      ? "synthetic_mechanics_only"
      : "exploratory_provisional",
    referenceCounts: {
      independentlyReviewed: 0,
      provisional: labelled.length,
      unverified: rows.length - labelled.length,
    },
    scheduled: rows.length,
    outcomes: Object.fromEntries(
      OUTCOMES.map((o) => [
        o,
        rows.filter((r) => r.prediction.outcome === o).length,
      ]),
    ),
    namedOutputs: rows.filter((r) =>
      r.prediction.outcome === "normalized" &&
      r.prediction.subject === "biological" &&
      r.prediction.resolution === "named"
    ).length,
    provisionalAgreement: {
      subject: rate(
        labelled.filter((r) => r.assessment!.subjectCorrect).length,
        labelled.length,
      ),
      exactSpecies: rate(
        species.filter((r) => r.assessment!.exactSpecies).length,
        species.length,
      ),
      offeredIdentity: rate(
        named.filter((r) => r.assessment!.correct).length,
        named.length,
      ),
      unresolved: rate(
        unresolved.filter((r) => r.assessment!.appropriateUnresolved).length,
        unresolved.length,
      ),
      strongDisagreement: rate(
        strong.filter((r) => !r.assessment!.correct).length,
        strong.length,
      ),
    },
  };
}
export async function generateExploratoryReport(
  corpusValue: unknown,
  manifestValue: unknown,
  recordsValue: unknown[],
  taxonomyValue: unknown,
) {
  const { corpus, manifest, records } = await validateReportInputs(
    corpusValue,
    manifestValue,
    recordsValue,
    taxonomyValue,
  );
  check(corpus.kind === "exploratory" && manifest.spec.stage === "exploratory");
  const slices = [];
  for (const profile of manifest.spec.profiles) {
    const keys = new Set(
      manifest.order.filter((a) => a.profile === profile).map((a) => a.key),
    );
    for (const inputGroup of [...INPUT_GROUPS, "all_cases"] as const) {
      const cases = corpus.cases.filter((c) =>
        inputGroup === "all_cases" || c.input.inputGroup === inputGroup
      );
      const rows = records.filter((r) =>
        keys.has(r.key) &&
        cases.some((c) => c.input.caseId === r.prediction.caseId)
      );
      // Empty groups are explicitly untested; the corpus validator requires >=1 case.
      const agreement = cases.length
        ? exploratoryAgreement(
          { ...corpus, cases },
          rows.map((r) => r.prediction),
          profile,
        )
        : null;
      const p = performance(rows, 0, manifest.spec.mode === "live");
      const { perCorrectOfferedUpperUsd: _unused, ...cost } = p.cost;
      slices.push({
        profile,
        inputGroup,
        coverage: cases.length ? "covered" : "untested",
        agreement,
        performance: { timing: p.timing, cost },
      });
    }
  }
  return {
    version: "identification_exploratory_report_v1",
    runId: manifest.spec.runId,
    runDigest: await fingerprintJson(manifest),
    corpusDigest: manifest.spec.corpusDigest,
    mode: manifest.spec.mode,
    evidenceStatus: corpus.evidenceOrigin === "synthetic"
      ? "synthetic_mechanics_only"
      : "exploratory_provisional",
    reviewerKind: corpus.eligibility?.reviewerKind ?? "synthetic",
    verdict: "measurement_only",
    baselineQualification: "not_independently_verified",
    completeness:
      records.some((r) =>
          ["unattempted", "unknown_execution"].includes(r.prediction.outcome)
        )
        ? "incomplete"
        : "complete",
    boundary: manifest.boundary,
    referenceCounts: {
      independentlyReviewed: 0,
      provisional:
        corpus.cases.filter((c) => c.provisionalReference !== null).length,
      unverified:
        corpus.cases.filter((c) => c.provisionalReference === null).length,
    },
    scheduled: records.length,
    attempted:
      records.filter((r) => r.prediction.outcome !== "unattempted").length,
    preflightMaximumUsd: manifest.pricing
      ? manifest.order.reduce((n, a) => n + a.reservedUsd, 0)
      : null,
    approvedBudgetUsd: manifest.spec.budgetUsd,
    slices,
  };
}
export type ExploratoryReport = Awaited<
  ReturnType<typeof generateExploratoryReport>
>;
export function renderExploratoryReport(r: ExploratoryReport): string {
  const lines = [
    "# Exploratory identification benchmark",
    "",
    `Run: ${r.runId}. Mode: ${r.mode}. Evidence: **${r.evidenceStatus}**. Status: ${r.completeness}.`,
    "",
    `Attempted ${r.attempted}/${r.scheduled}. References: ${r.referenceCounts.provisional} provisional, ${r.referenceCounts.unverified} unverified, 0 independently reviewed.`,
    "",
    "Reference agreement is provisional. Unverified references are excluded from every quality denominator. This report does not qualify a provider switch or establish independently verified biological accuracy. Offline/synthetic results contain no measured provider quality, latency or spending. Timings exclude capture, upload, hydration, persistence and app rendering.",
    "",
    "| Profile | Input | Cases | Provisional / unverified | Named agreement | Provider p50 / p95 ms | Estimated total USD |",
    "| --- | --- | ---: | --- | --- | --- | --- |",
  ];
  for (const s of r.slices) {
    const a = s.agreement,
      m = a?.provisionalAgreement.offeredIdentity,
      t = s.performance.timing.successfulIdentification;
    lines.push(
      `| ${s.profile} | ${s.inputGroup} | ${a?.scheduled ?? 0} | ${
        a
          ? `${a.referenceCounts.provisional} / ${a.referenceCounts.unverified}`
          : "untested"
      } | ${m ? `${m.numerator}/${m.denominator}` : "not estimable"} | ${
        r.mode === "offline"
          ? "not measured"
          : `${t.p50 ?? "unknown"} / ${t.p95 ?? "unknown"}`
      } | ${s.performance.cost.totalUpperUsd ?? "not measured / unknown"} |`,
    );
  }
  lines.push(
    "",
    "Complete failure counts, provisional subject/species/uncertainty agreement and cost gaps are in summary.json. Durable results contain bounded decisions, usage and timing only. Missing usage is unknown, never zero. Preflight reservations and local budgets are conservative safeguards, not invoice-exact hard caps.",
    "",
  );
  return lines.join("\n");
}
export async function saveExploratoryReport(root: string, runId: string) {
  const directory = join(root, "runs", runId);
  return await withRunLock(directory, async () => {
    const manifest = parseManifest(
      await readJson(join(directory, "manifest.json")),
    );
    const report = await generateExploratoryReport(
      await readJson(join(root, "corpus.json")),
      manifest,
      await readRecords(directory, manifest),
      await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
    );
    await atomicJson(join(directory, "summary.json"), report);
    await atomicText(
      join(directory, "report.md"),
      renderExploratoryReport(report),
    );
    return report;
  });
}
