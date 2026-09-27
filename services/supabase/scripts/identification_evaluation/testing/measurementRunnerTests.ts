import { validateSelection } from "../admission.ts";
import {
  assert,
  assertAlmostEquals,
  assertEquals,
  assertRejects,
} from "@std/assert";
import { join } from "node:path";
import { main } from "../../evaluate_identification.ts";
import { fingerprintJson } from "../evidence.ts";
import {
  fingerprintRunCorpus,
  parseExploratoryCorpus,
  parseRunCorpus,
} from "../exploratory.ts";
import { compareExploratoryRuns } from "../exploratoryComparison.ts";
import { measurementSlice } from "../exploratoryMeasurement.ts";
import { generateExploratoryReport } from "../exploratoryReport.ts";
import { atomicJson, readJson } from "../files.ts";
import { createMeasurementDemo, offlineOutcomes } from "../offline.ts";
import { estimateCost } from "../profiles.ts";
import { emptyRecord } from "../projection.ts";
import {
  parseAttempt,
  parseEvaluationPricing,
  parseManifest,
  parseRunSpec,
  parseTaxonomy,
  type SourceIdentity,
} from "../runContracts.ts";
import { executeRun, prepareRun, readRecords } from "../runner.ts";

const source: SourceIdentity = {
  commit: "0".repeat(40),
  dirty: true,
  digest: "1".repeat(64),
  sdk: "npm:@google/genai@2.23.0",
};
export function registerMeasurementTests(scratch: string) {
  Deno.test("measurement live hold rejects a valid provider packet before credential access while v1 eligibility remains intact", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "measurement-hold-",
    });
    try {
      await createMeasurementDemo(root);
      const inputs = await prepareRun(root, source, "offline");
      assert(
        inputs.corpus.kind === "exploratory" &&
          inputs.taxonomy.version === "evaluation_taxonomy_v2",
      );
      const corpus = parseExploratoryCorpus({
        ...inputs.corpus,
        evidenceOrigin: "real",
        eligibility: {
          recordRef: "synthetic-review",
          reviewerRef: "r0001",
          reviewerKind: "automated",
          retainUntil: "2027-01-01",
        },
        cases: inputs.corpus.cases.map((c) => ({
          ...c,
          curation: {
            kind: "eligibility_reviewed",
            source: "purpose_collected",
            sourceRecordRef: "synthetic-source",
            referenceRecordRef: "synthetic-reference",
            permission: "gemini_evaluation",
            rightsApproved: true,
            personalDataExcluded: true,
            nearDuplicatesReviewed: true,
          },
        })),
      });
      const spec = parseRunSpec({
        ...inputs.manifest.spec,
        mode: "live",
        profiles: ["gemini_pro"],
        corpusDigest: await fingerprintRunCorpus(corpus),
        budgetUsd: 10,
        pricingDigest: "2".repeat(64),
        readinessDigest: "3".repeat(64),
      });
      await atomicJson(join(root, "corpus.json"), corpus);
      await atomicJson(join(root, "spec.json"), spec);
      await assertRejects(
        () => prepareRun(root, source, "live"),
        Error,
        "evaluation_measurement_live_pending",
      );
      const legacy = parseTaxonomy({
        version: "evaluation_taxonomy_v1",
        taxonomyVersion: inputs.taxonomy.taxonomyVersion,
        taxa: inputs.taxonomy.taxa.map((t) => ({
          taxon: t.taxon,
          names: [t.canonicalName, ...t.synonyms],
        })),
      });
      await validateSelection(corpus, {
        ...spec,
        taxonomyDigest: await fingerprintJson(legacy),
      }, legacy);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("measurement CLI preserves v2 projections, refuses incompatible comparisons, and regenerates without evidence files", async () => {
    const parent = await Deno.makeTempDir({
        dir: scratch,
        prefix: "measurement-",
      }),
      root = join(parent, "packet"),
      runId = "offline-measurement-v2";
    try {
      await main(["demo-measurement", root]);
      const directory = join(root, "runs", runId),
        manifest = parseManifest(
          await readJson(join(directory, "manifest.json")),
        );
      const corpus = parseRunCorpus(await readJson(join(root, "corpus.json"))),
        taxonomy = await readJson(join(root, "taxonomy.json"));
      const records = await readRecords(directory, manifest);
      const summary = await readJson(join(directory, "summary.json")) as {
        version: string;
        explanationQuality: string;
      };
      assertEquals(summary.version, "identification_exploratory_report_v2");
      assertEquals(
        summary.explanationQuality,
        "not_measured_brevity_candidate_deferred",
      );
      assert(records.every((r) => r.version.endsWith("_v2")));
      const comparison = await compareExploratoryRuns(
        corpus,
        taxonomy,
        manifest,
        records,
        manifest,
        records,
        { leftProfile: "gemini_pro", rightProfile: "openai_gpt_6_sol" },
      );
      assertEquals(comparison.verdict, "measurement_only");
      assertEquals(comparison.cacheComparability, "not_established");
      const all = comparison.slices.find((s) => s.inputGroup === "all_cases")!;
      assertEquals(all.baseline.scheduled, 4);
      assertEquals(all.paired.length, 4);
      assertEquals(all.baseline.outcomes.operational_failure, 1);
      assertEquals(all.observedLatencyImprovementPercent, null);
      assertEquals(all.observedCostImprovementPercent, null);
      assertEquals(
        comparison.slices.find((s) => s.inputGroup === "photos")?.baseline
          .scheduled,
        2,
      );
      assertEquals(
        comparison.slices.find((s) => s.inputGroup === "description")?.baseline
          .scheduled,
        2,
      );
      await assertRejects(() =>
        compareExploratoryRuns(
          corpus,
          taxonomy,
          manifest,
          records,
          {
            ...manifest,
            source: { ...manifest.source, digest: "9".repeat(64) },
          },
          records,
          { leftProfile: "gemini_pro", rightProfile: "openai_gpt_6_sol" },
        )
      );
      await assertRejects(() =>
        generateExploratoryReport(
          corpus,
          { ...manifest, scorerVersion: "identification_decisions_v1" },
          records,
          taxonomy,
        )
      );
      const changed = structuredClone(records),
        mapped = changed.find((r) =>
          r.prediction.outcome === "normalized" && r.prediction.taxon !== null
        )!;
      assert(mapped.prediction.outcome === "normalized");
      mapped.prediction = {
        ...mapped.prediction,
        taxon: { id: "synthetic:not-in-catalog", rank: "species" },
      };
      await assertRejects(() =>
        generateExploratoryReport(corpus, manifest, changed, taxonomy)
      );
      await Deno.remove(join(root, "assets"), { recursive: true });
      await main(["report", root, runId]);
      assertEquals(await readJson(join(directory, "summary.json")), summary);
      await main([
        "compare-exploratory",
        root,
        runId,
        runId,
        "gemini_pro",
        "openai_gpt_6_sol",
      ]);
      assertEquals(
        await readJson(
          join(
            root,
            `comparison-exploratory-${runId}-${runId}-gemini_pro-openai_gpt_6_sol.json`,
          ),
        ),
        comparison,
      );
      await assertRejects(() =>
        main(["compare", root, runId, runId, "gemini_pro", "openai_gpt_6_sol"])
      );
    } finally {
      await Deno.remove(parent, { recursive: true });
    }
  });

  Deno.test("measurement crash recovery preserves unknown v2 attempts and refuses a taxonomy switch during resume", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "measurement-crash-",
    });
    try {
      await createMeasurementDemo(root);
      const inputs = await prepareRun(root, source, "offline"),
        outcome = offlineOutcomes(
          await readJson(join(root, "fixtures.json")),
          inputs.corpus,
          inputs.manifest.spec,
        );
      let calls = 0;
      await assertRejects(() =>
        executeRun(root, inputs, {
          offlineOutcome: (i, a) => {
            calls++;
            return outcome(i, a);
          },
          checkpoint: (point) => {
            if (point === "after_claim") {
              throw new Error("synthetic_interruption");
            }
          },
        })
      );
      const resumed = await executeRun(root, inputs, {
        offlineOutcome: (i, a) => {
          calls++;
          return outcome(i, a);
        },
      });
      assertEquals(calls, 0);
      assertEquals(resumed.stopReason, "interrupted_attempt");
      assertEquals(resumed.records[0].prediction.outcome, "unknown_execution");
      assert(resumed.records.every((r) => r.version.endsWith("_v2")));
      const report = await generateExploratoryReport(
        inputs.corpus,
        inputs.manifest,
        resumed.records,
        inputs.taxonomy,
      );
      assertEquals(report.completeness, "incomplete");
      assert(inputs.taxonomy.version === "evaluation_taxonomy_v2");
      const changed = {
        ...inputs.taxonomy,
        reviewRef: "synthetic-changed-review",
      };
      await atomicJson(join(root, "taxonomy.json"), changed);
      await atomicJson(join(root, "spec.json"), {
        ...inputs.manifest.spec,
        taxonomyDigest: await fingerprintJson(changed),
      });
      await assertRejects(
        () =>
          validateSelection(inputs.corpus, {
            ...inputs.manifest.spec,
            mode: "live",
          }, inputs.taxonomy),
        Error,
        "evaluation_measurement_live_pending",
      );
      const newInputs = await prepareRun(root, source, "offline");
      await assertRejects(() =>
        executeRun(root, newInputs, { offlineOutcome: outcome })
      );
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });

  Deno.test("fixed-population metrics retain expensive outliers, missing durations and unknown/unattempted outcomes", async () => {
    const root = await Deno.makeTempDir({
      dir: scratch,
      prefix: "measurement-metrics-",
    });
    try {
      await createMeasurementDemo(root);
      const inputs = await prepareRun(root, source, "offline");
      assert(inputs.corpus.kind === "exploratory");
      const pricing = parseEvaluationPricing({
        version: "evaluation_pricing_v1",
        currency: "USD",
        service: "paid_standard_synchronous",
        retrievedAt: "2026-09-25T00:00:00.000Z",
        sourceUrl: "https://ai.google.dev/gemini-api/docs/pricing",
        reviewRef: "synthetic-price",
        includesReasoning: true,
        models: ["gemini-2.5-flash", "gemini-2.5-pro"].map((model) => ({
          model,
          inputPerMillion: { text: 1, image: 1, audio: 1, cached: .1 },
          outputPerMillion: 1,
          maxInputTokens: 10000,
          maxBillableOutputTokens: 8192,
          limitsEvidenceRef: "synthetic-limits",
        })),
      });
      // Pure aggregation over invented live-shaped records, never live admission or dispatch.
      const manifest = {
        ...inputs.manifest,
        pricing,
        spec: { ...inputs.manifest.spec, mode: "live" as const },
      };
      const assignments = manifest.order.filter((a) =>
        a.profile === "gemini_pro"
      );
      const times = [10, 20, 30, 1000], tokens = [100, 100, 100, 5000];
      const records = assignments.map((a, i) => {
        const usage = {
          promptTokens: tokens[i],
          candidateTokens: 10,
          thinkingTokens: 0,
          totalTokens: tokens[i] + 10,
          cachedTokens: 0,
          cacheWriteTokens: null,
          toolTokens: 0,
          modalities: null,
        };
        return parseAttempt({
          ...emptyRecord(a, "0".repeat(64), "unattempted", true),
          prediction: {
            caseId: a.caseId,
            outcome: "normalized",
            subject: "biological",
            resolution: "unresolved",
            taxon: null,
            confidence: 0,
          },
          reason: "completed",
          returnedModel: a.model,
          band: "below_possible",
          mapping: { status: "not_applicable", match: null },
          providerMs: times[i],
          normalizationMs: 1,
          usage,
          estimatedUpperUsd: estimateCost(pricing, a.model, usage),
        });
      });
      const all = measurementSlice(
        inputs.corpus,
        manifest,
        records,
        "gemini_pro",
        "all_cases",
      );
      assertEquals(all.timing.successfulIdentification.medianMs, 25);
      assertEquals(all.timing.latencyEligible, true);
      assertAlmostEquals(all.cost.totalEstimatedUsd!, 5340 / 1e6);
      assertEquals(all.cost.knownAttempts, 4);
      const photo = measurementSlice(
          inputs.corpus,
          manifest,
          records,
          "gemini_pro",
          "photos",
        ),
        text = measurementSlice(
          inputs.corpus,
          manifest,
          records,
          "gemini_pro",
          "description",
        );
      assertEquals(photo.scheduled, 2);
      assertEquals(text.scheduled, 2);
      assertAlmostEquals(
        photo.cost.totalEstimatedUsd! + text.cost.totalEstimatedUsd!,
        all.cost.totalEstimatedUsd!,
      );
      records[0].providerMs = null;
      const missing = measurementSlice(
        inputs.corpus,
        manifest,
        records,
        "gemini_pro",
        "all_cases",
      );
      assertEquals(missing.timing.latencyEligible, false);
      assertEquals(missing.timing.missingProviderDurations, 1);
      records[0] = emptyRecord(
        assignments[0],
        "0".repeat(64),
        "interrupted_attempt",
        true,
      );
      records[1] = emptyRecord(
        assignments[1],
        "0".repeat(64),
        "unattempted",
        true,
      );
      const incomplete = measurementSlice(
        inputs.corpus,
        manifest,
        records,
        "gemini_pro",
        "all_cases",
      );
      assertEquals(incomplete.scheduled, 4);
      assertEquals(incomplete.outcomes.unknown_execution, 1);
      assertEquals(incomplete.outcomes.unattempted, 1);
      assertEquals(incomplete.cost.totalEstimatedUsd, null);
      assertEquals(incomplete.cost.incompleteAttempts, 2);
      assertAlmostEquals(incomplete.cost.knownEstimatedUsd!, 5120 / 1e6);
    } finally {
      await Deno.remove(root, { recursive: true });
    }
  });
}
