import { join } from "node:path";
import { validateSelection } from "./admission.ts";
import {
  INPUT_GROUPS,
  type Rate,
  SCORER_VERSION,
  type ScoreReport,
} from "./contracts.ts";
import { fingerprintEvidence, fingerprintJson } from "./evidence.ts";
import {
  fingerprintRunCorpus,
  parseRunCorpus,
  type RunCorpus,
} from "./exploratory.ts";
import { atomicJson, atomicText, readJson, withRunLock } from "./files.ts";
import {
  confidencePolicy,
  estimateCost,
  interleave,
  random,
  reserveCost,
} from "./profiles.ts";
import {
  type AttemptRecord,
  parseAttempt,
  parseManifest,
  parseTaxonomy,
  type RunManifest,
} from "./runContracts.ts";
import { guardNextAttempt, readRecords, validateRecord } from "./runner.ts";
import { assessDecision, scoreEvaluation } from "./scoring.ts";
import { requireCondition as check } from "./validation.ts";

export const INTERVAL_METHOD =
  "wilson95-paired-group-percentile3000-lcg1664525-v1";
export const RESAMPLE_SEED = 20260922;
export function wilson95(rate: Rate) {
  if (!rate.denominator) {
    return { lower: null, upper: null, status: "not_estimable" as const };
  }
  const n = rate.denominator, p = rate.numerator / n, z = 1.959963984540054;
  const divisor = 1 + z * z / n,
    center = (p + z * z / (2 * n)) / divisor,
    radius = z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / divisor;
  return {
    lower: Math.max(0, center - radius),
    upper: Math.min(1, center + radius),
    status: "measured" as const,
  };
}
export function percentiles(values: number[]) {
  const sorted = values.toSorted((a, b) => a - b);
  const at = (p: number) =>
    sorted.length
      ? sorted[Math.max(0, Math.ceil(p * sorted.length) - 1)]
      : null;
  return { count: sorted.length, p50: at(.5), p95: at(.95) };
}
export function performance(
  rows: AttemptRecord[],
  correct: number,
  live: boolean,
) {
  const attempted = rows.filter((r) => r.prediction.outcome !== "unattempted");
  const completed = attempted.filter((r) =>
    ["normalized", "refusal", "invalid_output"].includes(r.prediction.outcome)
  );
  const times = (rs: AttemptRecord[]) =>
    rs.flatMap((r) => r.providerMs === null ? [] : [r.providerMs]);
  const known = attempted.reduce((n, r) => n + (r.estimatedUpperUsd ?? 0), 0);
  const unknown = attempted.filter((r) => r.estimatedUpperUsd === null).length;
  return {
    timing: {
      unit: "ms",
      completedProvider: percentiles(times(completed)),
      successfulIdentification: percentiles(
        times(attempted.filter((r) => r.prediction.outcome === "normalized")),
      ),
      normalization: percentiles(
        attempted.flatMap((r) =>
          r.normalizationMs === null ? [] : [r.normalizationMs]
        ),
      ),
      failures: percentiles(
        times(attempted.filter((r) => r.prediction.outcome !== "normalized")),
      ),
      unknownExecutions:
        attempted.filter((r) => r.prediction.outcome === "unknown_execution")
          .length,
      missingProviderDurations:
        attempted.filter((r) => r.providerMs === null).length,
    },
    cost: {
      currency: "USD",
      method: live
        ? "conservative_usage_upper_estimate"
        : "not_measured_offline",
      knownComponentUpperUsd: live ? known : null,
      unknownCalls: live ? unknown : 0,
      totalUpperUsd: live && !unknown ? known : null,
      perAttemptUpperUsd: live && !unknown && attempted.length
        ? known / attempted.length
        : null,
      perCorrectOfferedUpperUsd: live && !unknown && correct
        ? known / correct
        : null,
      missingModalityDetails:
        attempted.filter((r) => r.usage?.modalities === null || !r.usage)
          .length,
    },
  };
}
export async function validateReportInputs(
  corpusValue: unknown,
  manifestValue: unknown,
  recordValues: unknown[],
  taxonomyValue: unknown,
) {
  const corpus = parseRunCorpus(corpusValue),
    manifest = parseManifest(manifestValue),
    records = recordValues.map(parseAttempt);
  await validateSelection(corpus, manifest.spec, parseTaxonomy(taxonomyValue));
  check(
    await fingerprintRunCorpus(corpus) === manifest.spec.corpusDigest &&
      corpus.taxonomyVersion === manifest.taxonomyVersion &&
      corpus.preparationVersion === manifest.preparationVersion,
  );
  check(manifest.scorerVersion === SCORER_VERSION);
  check(
    records.length === manifest.order.length &&
      new Set(records.map((r) => r.key)).size === records.length,
  );
  check(
    manifest.spec.caseIds.every((id) =>
      corpus.cases.some((c) =>
        c.input.caseId === id && c.input.split === manifest.spec.split
      )
    ),
  );
  check(
    await fingerprintJson(
      interleave(manifest.order, manifest.spec.orderSeed),
    ) === await fingerprintJson(manifest.order),
  );
  if (manifest.pricing) {
    check(
      await fingerprintJson(manifest.pricing) === manifest.spec.pricingDigest,
    );
  }
  const digest = await fingerprintJson(manifest);
  for (const a of manifest.order) {
    const r = records.find((r) => r.key === a.key)!;
    check(
      a.inputDigest === await fingerprintEvidence(
        corpus.cases.find((c) => c.input.caseId === a.caseId)!.input,
      ),
    );
    check(r && r.runDigest === digest && r.prediction.caseId === a.caseId);
    check(
      a.confidenceDigest === await fingerprintJson(confidencePolicy(a.profile)),
    );
    if (r.prediction.outcome !== "unattempted") {
      validateRecord(r, a, digest, manifest.pricing);
    }
    if (manifest.pricing) {
      check(a.reservedUsd === reserveCost(manifest.pricing, a.model));
      check(
        r.estimatedUpperUsd ===
          estimateCost(manifest.pricing, a.model, r.usage),
      );
    }
    if (r.prediction.outcome === "normalized") {
      const p = confidencePolicy(a.profile),
        confidence = r.prediction.confidence;
      check(
        r.band ===
            (confidence >= p.strong
              ? "strong"
              : confidence >= p.possible
              ? "possible"
              : "below_possible") &&
          r.diagnostic === (confidence >= p.diagnostic),
      );
    }
  }
  return { corpus, manifest, records };
}
export async function generateReport(
  corpusValue: unknown,
  manifestValue: unknown,
  recordValues: unknown[],
  taxonomyValue: unknown,
) {
  const { corpus, manifest, records } = await validateReportInputs(
    corpusValue,
    manifestValue,
    recordValues,
    taxonomyValue,
  );
  check(corpus.kind !== "exploratory");
  const slices = [];
  for (let attempt = 1; attempt <= manifest.spec.repeats; attempt++) {
    for (const profile of manifest.spec.profiles) {
      const keys = new Set(
        manifest.order.filter((a) =>
          a.attempt === attempt && a.profile === profile
        ).map((a) => a.key),
      );
      const rows = records.filter((r) => keys.has(r.key));
      for (const inputGroup of [...INPUT_GROUPS, "all_cases"] as const) {
        const selectedRows = rows.filter((r) =>
          inputGroup === "all_cases" ||
          corpus.cases.find((c) => c.input.caseId === r.prediction.caseId)!
              .input.inputGroup === inputGroup
        );
        const score = await scoreEvaluation(
          corpus,
          rows.map((r) => r.prediction),
          {
            profile,
            split: manifest.spec.split,
            caseIds: manifest.spec.caseIds,
            ...(inputGroup === "all_cases" ? {} : { inputGroup }),
          },
        );
        slices.push({
          attempt,
          profile,
          inputGroup,
          score,
          intervals: Object.fromEntries(
            Object.entries(score.metrics).map((
              [name, rate],
            ) => [name, wilson95(rate)]),
          ),
          reliabilityIntervals: Object.fromEntries(
            Object.entries(score.reliability).map((
              [name, bin],
            ) => [name, wilson95(bin.correctness)]),
          ),
          performance: performance(
            selectedRows,
            score.metrics.offeredPrecision.numerator,
            manifest.spec.mode === "live",
          ),
        });
      }
    }
  }
  const flags = records.map((r) => ({
    key: r.key,
    ...assessDecision(
      corpus.cases.find((c) => c.input.caseId === r.prediction.caseId)!,
      r.prediction,
    ),
  }));
  const next = manifest.order.find((a) =>
    records.find((r) => r.key === a.key)!.prediction.outcome === "unattempted"
  );
  const stoppingReasons = [
    ...new Set(
      records.filter((r) =>
        (manifest.spec.mode === "live" || r.reason === "interrupted_attempt") &&
        [
          "interrupted_attempt",
          "unknown_execution",
          "operational_failure",
          "model_mismatch",
          "usage_missing",
        ].includes(r.reason)
      ).map((r) => r.reason),
    ),
  ];
  const guardReason = next
    ? guardNextAttempt(
      records,
      manifest.spec.maxCalls,
      manifest.spec.budgetUsd,
      next.reservedUsd,
      manifest.spec.mode === "live",
    )
    : null;
  return {
    version: "identification_run_report_v1",
    runDigest: await fingerprintJson(manifest),
    corpusDigest: manifest.spec.corpusDigest,
    mode: manifest.spec.mode,
    evidenceKind: corpus.kind,
    stage: manifest.spec.stage,
    boundary: manifest.boundary,
    verdict: "measurement_only",
    completeness:
      records.some((r) =>
          ["unattempted", "unknown_execution"].includes(r.prediction.outcome)
        )
        ? "incomplete"
        : "complete",
    aggregate: "balanced_corpus_not_production_prevalence",
    intervalMethod: INTERVAL_METHOD,
    resampleSeed: RESAMPLE_SEED,
    scheduled: records.length,
    attempted:
      records.filter((r) => r.prediction.outcome !== "unattempted").length,
    preflightMaximumUsd: manifest.pricing
      ? manifest.order.reduce((n, a) => n + a.reservedUsd, 0)
      : null,
    approvedBudgetUsd: manifest.spec.budgetUsd,
    stoppingReasons: [
      ...stoppingReasons,
      ...(guardReason ? [guardReason] : []),
    ],
    slices,
    flags,
  };
}
export type RunReport = Awaited<ReturnType<typeof generateReport>>;
export function renderReport(r: RunReport): string {
  const pct = (rate: Rate) =>
    `${rate.numerator}/${rate.denominator} (${
      rate.value === null
        ? "not estimable"
        : (rate.value * 100).toFixed(1) + "%"
    })`;
  const lines = [
    "# Identification evaluation",
    "",
    `Mode: ${r.mode}. Evidence: ${r.evidenceKind}. Stage: ${r.stage}.`,
    "",
    `Verdict: **measurement_only**. Run: **${r.completeness}**. Attempted ${r.attempted}/${r.scheduled}.`,
    "",
    "These measurements exclude capture/upload, hydration, persistence and app rendering. Synthetic/offline results provide no biological quality, provider latency or billing evidence. Repeats are reported separately. The aggregate reflects this corpus, not production prevalence.",
    "",
    "| Profile | Attempt | Input | Cases | Exact species | Offered precision | Coverage | Correct yield | Strong errors |",
    "| --- | ---: | --- | ---: | --- | --- | --- | --- | --- |",
  ];
  for (const s of r.slices) {
    lines.push(
      `| ${s.profile} | ${s.attempt} | ${s.inputGroup} | ${s.score.counts.scheduled} | ${
        pct(s.score.metrics.exactSpecies)
      } | ${pct(s.score.metrics.offeredPrecision)} | ${
        pct(s.score.metrics.answerCoverage)
      } | ${pct(s.score.metrics.correctAnswerYield)} | ${
        pct(s.score.metrics.strongErrorRate)
      } |`,
    );
  }
  lines.push(
    "",
    `95% proportion intervals: Wilson. Paired comparisons: group bootstrap, 3,000 draws, seed ${RESAMPLE_SEED}. Method: ${INTERVAL_METHOD}. Counts, intervals, confusion matrices, reliability, failure categories, timing and conservative cost details are in summary.json.`,
    "",
    "Cost estimates use the reviewed worst-case modality rate and include thinking tokens. Missing billable usage is unknown, never zero. The known component is an upper estimate for known calls, not an invoice lower bound or a hard billing cap.",
    "",
    `Approved budget: USD ${r.approvedBudgetUsd}. Full-schedule conservative reservation: ${
      r.preflightMaximumUsd === null
        ? "not measured"
        : "USD " + r.preflightMaximumUsd.toFixed(6)
    }.`,
    "",
  );
  return lines.join("\n");
}
export async function saveReport(
  root: string,
  runId: string,
): Promise<RunReport> {
  const directory = join(root, "runs", runId);
  return await withRunLock(directory, async () => {
    const corpus = await readJson(join(root, "corpus.json")),
      manifest = parseManifest(
        await readJson(join(directory, "manifest.json")),
      );
    const report = await generateReport(
      corpus,
      manifest,
      await readRecords(directory, manifest),
      await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
    );
    await atomicJson(join(directory, "summary.json"), report);
    await atomicText(join(directory, "report.md"), renderReport(report));
    return report;
  });
}

/** Paired group bootstrap of ratios. Undefined replicates are NOT discarded to
 * manufacture a narrow interval: any zero denominator marks it not estimable.
 */
export function pairedInterval(
  left: Rate[],
  right: Rate[],
  seed = RESAMPLE_SEED,
) {
  check(left.length === right.length && left.length > 0);
  const rng = random(seed), values: number[] = [];
  for (let draw = 0; draw < 3000; draw++) {
    let ln = 0, ld = 0, rn = 0, rd = 0;
    for (let i = 0; i < left.length; i++) {
      const index = Math.floor(rng() * left.length);
      ln += left[index].numerator;
      ld += left[index].denominator;
      rn += right[index].numerator;
      rd += right[index].denominator;
    }
    if (!ld || !rd) {
      return {
        lower: null,
        upper: null,
        status: "not_estimable",
        method: INTERVAL_METHOD,
        seed,
      };
    }
    values.push(rn / rd - ln / ld);
  }
  values.sort((a, b) => a - b);
  return {
    lower: values[74],
    upper: values[2924],
    status: "measured",
    method: INTERVAL_METHOD,
    seed,
  };
}
export async function compareRuns(
  corpus: RunCorpus,
  taxonomyValue: unknown,
  leftManifest: RunManifest,
  leftRecords: AttemptRecord[],
  rightManifest: RunManifest,
  rightRecords: AttemptRecord[],
  options: {
    leftProfile: RunManifest["spec"]["profiles"][number];
    rightProfile: RunManifest["spec"]["profiles"][number];
    allowProfileDifference?: boolean;
  },
) {
  check(corpus.kind !== "exploratory");
  const l = await validateReportInputs(
      corpus,
      leftManifest,
      leftRecords,
      taxonomyValue,
    ),
    r = await validateReportInputs(
      corpus,
      rightManifest,
      rightRecords,
      taxonomyValue,
    );
  for (
    const field of [
      "boundary",
      "scorerVersion",
      "taxonomyVersion",
      "preparationVersion",
    ] as const
  ) check(l.manifest[field] === r.manifest[field]);
  for (
    const field of [
      "corpusDigest",
      "taxonomyDigest",
      "split",
      "stage",
      "mode",
      "repeats",
      "orderSeed",
    ] as const
  ) check(l.manifest.spec[field] === r.manifest.spec[field]);
  check(
    await fingerprintJson(l.manifest.source) ===
      await fingerprintJson(r.manifest.source),
  );
  check(
    await fingerprintJson(l.manifest.spec.caseIds.toSorted()) ===
      await fingerprintJson(r.manifest.spec.caseIds.toSorted()),
  );
  check(
    options.leftProfile === options.rightProfile ||
      options.allowProfileDifference === true,
  );
  check(
    leftManifest.spec.profiles.includes(options.leftProfile) &&
      rightManifest.spec.profiles.includes(options.rightProfile),
  );
  check(
    [...leftRecords, ...rightRecords].every((row) =>
      !["unattempted", "unknown_execution", "local_validation_failure"]
        .includes(row.prediction.outcome)
    ),
  );
  const differences = [], paired = [];
  for (let attempt = 1; attempt <= leftManifest.spec.repeats; attempt++) {
    const singles: { left: ScoreReport; right: ScoreReport; group: string }[] =
      [];
    for (const caseId of leftManifest.spec.caseIds) {
      const a = leftManifest.order.find((a) =>
        a.caseId === caseId && a.profile === options.leftProfile &&
        a.attempt === attempt
      )!;
      const b = rightManifest.order.find((a) =>
        a.caseId === caseId && a.profile === options.rightProfile &&
        a.attempt === attempt
      )!;
      check(a.inputDigest === b.inputDigest);
      const la = leftRecords.find((r) => r.key === a.key)!,
        rb = rightRecords.find((r) => r.key === b.key)!;
      check(la.returnedModel === a.model && rb.returnedModel === b.model);
      const config = (a: typeof b) => ({
        model: a.model,
        policy: a.policyDigest,
        prompt: a.promptDigest,
        schema: a.schemaDigest,
        confidence: a.confidenceDigest,
        timeout: a.timeoutMs,
        generation: a.generation,
      });
      if (options.leftProfile === options.rightProfile) {
        check(
          a.requestDigest === b.requestDigest &&
            await fingerprintJson(config(a)) ===
              await fingerprintJson(config(b)),
        );
      } else {differences.push({
          caseId,
          attempt,
          left: config(a),
          right: config(b),
        });}
      singles.push({
        left: await scoreEvaluation(corpus, [la.prediction], {
          profile: options.leftProfile,
          split: leftManifest.spec.split,
          caseIds: [caseId],
        }),
        right: await scoreEvaluation(corpus, [rb.prediction], {
          profile: options.rightProfile,
          split: rightManifest.spec.split,
          caseIds: [caseId],
        }),
        group: corpus.cases.find((c) =>
          c.input.caseId === caseId
        )!.input.inputGroup,
      });
    }
    for (const inputGroup of [...INPUT_GROUPS, "all_cases"]) {
      const rows = singles.filter((s) =>
        inputGroup === "all_cases" || s.group === inputGroup
      );
      if (!rows.length) continue;
      paired.push({
        attempt,
        inputGroup,
        metrics: Object.fromEntries(
          (Object.keys(
            rows[0].left.metrics,
          ) as (keyof ScoreReport["metrics"])[]).map(
            (key) => [
              key,
              pairedInterval(
                rows.map((s) => s.left.metrics[key]),
                rows.map((s) => s.right.metrics[key]),
              ),
            ],
          ),
        ),
      });
    }
  }
  return {
    version: "identification_comparison_v1",
    verdict: "measurement_only",
    compatible: true,
    leftDigest: await fingerprintJson(leftManifest),
    rightDigest: await fingerprintJson(rightManifest),
    assignmentDifferences: differences,
    paired,
    costComparable: leftManifest.spec.mode === "live" &&
      [...leftRecords, ...rightRecords].every((r) =>
        r.estimatedUpperUsd !== null
      ) &&
      await fingerprintJson(leftManifest.pricing) ===
        await fingerprintJson(rightManifest.pricing),
  };
}
