/** Isolated filesystem suite: requires only the disposable directory argument,
 * repository source reads and a Deno child for the cross-process lock test.
 * No network or environment permission, and no provider is invoked.
 */
import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import { main } from "./evaluate_identification.ts";
import { interleave } from "./identification_evaluation/profiles.ts";
import { preflightCorpus } from "./identification_evaluation/preflight.ts";
import { saveExploratoryReport } from "./identification_evaluation/exploratoryReport.ts";
import {
  prepareEvidence,
  validateImage,
  validateWavContainer,
} from "./identification_evaluation/assets.ts";
import { fingerprintJson } from "./identification_evaluation/evidence.ts";
import {
  atomicJson,
  exists,
  readJson,
  withRunLock,
} from "./identification_evaluation/files.ts";
import {
  createDemo,
  offlineOutcomes,
} from "./identification_evaluation/offline.ts";
import {
  compareRuns,
  generateReport,
  saveReport,
} from "./identification_evaluation/reports.ts";
import {
  parseRunSpec,
  type SourceIdentity,
} from "./identification_evaluation/runContracts.ts";
import {
  executeRun,
  prepareRun,
  readRecords,
} from "./identification_evaluation/runner.ts";

import { admitAudioPromptComparisonObservation } from "./admit_audio_prompt_comparison_observation.ts";
import { audioPromptComparisonObservationFixture as promptFixture } from "./identification_evaluation/testing/audioPromptComparisonFixture.ts";
import { admitAudioComparisonObservation } from "./admit_audio_comparison_observation.ts";
import { audioComparisonObservationFixture as fixture } from "./identification_evaluation/testing/audioComparisonFixture.ts";

import { registerAudioPromptPacketTests } from "./identification_evaluation/testing/audioPromptPacketTests.ts";

import { registerAudioPromptExecutionTests } from "./identification_evaluation/testing/audioPromptExecutionTests.ts";

const scratch = Deno.args[0];
if (!scratch) throw new Error("evaluation_test_directory_required");
registerAudioPromptPacketTests(scratch);
registerAudioPromptExecutionTests(scratch);
const source: SourceIdentity = {
  commit: "0".repeat(40),
  dirty: true,
  digest: "1".repeat(64),
  sdk: "npm:@google/genai@2.23.0",
};
async function setup() {
  const root = await Deno.makeTempDir({ dir: scratch, prefix: "evaluation-" });
  await createDemo(root);
  const inputs = await prepareRun(root, source, "offline");
  const fixture = offlineOutcomes(
    await readJson(join(root, "fixtures.json")),
    inputs.corpus,
    inputs.manifest.spec,
  );
  return { root, inputs, fixture };
}

Deno.test("CLI exploratory demo, report and preflight retain their separate contract and reject formal comparison", async () => {
  const parent = await Deno.makeTempDir({ dir: scratch, prefix: "cli-" });
  const root = join(parent, "demo");
  const runId = "offline-exploratory-v1";
  try {
    await main(["demo-exploratory", root]);
    const summaryPath = join(root, "runs", runId, "summary.json");
    const summary = await readJson(summaryPath) as Record<string, unknown>;
    assertEquals(summary.version, "identification_exploratory_report_v1");
    assertEquals(summary.evidenceStatus, "synthetic_mechanics_only");
    await main(["preflight", root]);
    const preflight = await readJson(join(root, "preflight.json")) as Record<
      string,
      unknown
    >;
    assertEquals(preflight.dispatchAuthorized, false);
    await Deno.remove(join(root, "assets"), { recursive: true });
    await main(["report", root, runId]);
    assertEquals(await readJson(summaryPath), summary);
    await assertRejects(() =>
      main([
        "compare",
        root,
        runId,
        runId,
        "gemini_flash_free",
        "gemini_pro",
      ])
    );
    assertEquals(
      await exists(join(root, `comparison-${runId}-${runId}.json`)),
      false,
    );
  } finally {
    await Deno.remove(parent, { recursive: true });
  }
});

Deno.test("exploratory preflight and durable offline experiments retain unverified cases without formal scoring", async () => {
  const root = await Deno.makeTempDir({ dir: scratch, prefix: "exploratory-" });
  try {
    await createDemo(root, true);
    const p = await preflightCorpus(root, source);
    assertEquals(p.dispatchAuthorized, false);
    assertEquals(p.plannedCalls, 24);
    assertEquals(p.referenceLabels, 6);
    assertEquals(p.fullScheduleReservationUsd, null);
    assertEquals(await exists(join(root, "runs")), false);
    const inputs = await prepareRun(root, source, "offline");
    const fixture = offlineOutcomes(
      await readJson(join(root, "fixtures.json")),
      inputs.corpus,
      inputs.manifest.spec,
    );
    let calls = 0;
    const outcome = (
      i: Parameters<typeof fixture>[0],
      a: Parameters<typeof fixture>[1],
    ) => {
      calls++;
      return fixture(i, a);
    };
    await executeRun(root, inputs, { offlineOutcome: outcome });
    assertEquals(calls, 24);
    const report = await saveExploratoryReport(
      root,
      inputs.manifest.spec.runId,
    );
    assertEquals(report.referenceCounts, {
      independentlyReviewed: 0,
      provisional: 6,
      unverified: 6,
    });
    assertEquals(report.evidenceStatus, "synthetic_mechanics_only");
    assertEquals(report.completeness, "incomplete");
    assertEquals(report.slices.length, 14);
    await assertRejects(() => saveReport(root, inputs.manifest.spec.runId));
    await executeRun(root, inputs, { offlineOutcome: outcome });
    assertEquals(calls, 24);
    await Deno.remove(join(root, "assets"), { recursive: true });
    assertEquals(
      await saveExploratoryReport(root, inputs.manifest.spec.runId),
      report,
    );
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("offline end-to-end preserves complete media, normalizes fixtures and regenerates reports without assets", async () => {
  const { root, inputs, fixture } = await setup();
  try {
    const video = inputs.corpus.cases.find((c) =>
      c.input.inputGroup === "frames_audio"
    )!;
    const request = await prepareEvidence(root, video.input);
    assertEquals(request.evidence.filter((e) => e.kind === "image").length, 5);
    assertEquals(request.evidence.filter((e) => e.kind === "audio").length, 1);
    assertEquals(request.evidence.at(-1), {
      kind: "text",
      source: "capture_context",
      order: request.evidence.length - 1,
      text: "Context: no telemetry.",
    });
    const raw = JSON.stringify(request);
    for (
      const forbidden of [
        "acceptableTaxa",
        "reviewer",
        "reference",
        "synthetic:5",
        "c0005",
        "assets/",
      ]
    ) assert(!raw.includes(forbidden));
    let calls = 0;
    const result = await executeRun(root, inputs, {
      offlineOutcome: (i, a) => {
        calls++;
        return fixture(i, a);
      },
    });
    assertEquals(calls, 24);
    assertEquals(
      result.records.filter((r) => r.prediction.outcome === "normalized")
        .length,
      16,
    );
    assertEquals(
      result.records.filter((r) => r.prediction.outcome === "unknown_execution")
        .length,
      2,
    );
    const report = await saveReport(root, inputs.manifest.spec.runId);
    assertEquals(report.slices.length, 14);
    assertEquals(report.completeness, "incomplete");
    assertEquals(report.stoppingReasons, []);
    assertEquals(
      report.slices.find((s) => s.inputGroup === "all_cases")!.score.counts
        .named,
      6,
    );
    await Deno.remove(join(root, "assets"), { recursive: true });
    assertEquals(await saveReport(root, inputs.manifest.spec.runId), report);
    for await (const f of Deno.readDir(join(result.directory, "results"))) {
      const json = await Deno.readTextFile(
        join(result.directory, "results", f.name),
      );
      for (
        const forbidden of [
          "Syntheticus",
          "reasoning",
          "base64",
          "observationTexts",
          "inlineData",
          "credential",
        ]
      ) assert(!json.includes(forbidden));
    }
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
Deno.test("all inputs preflight before dispatch; hash mismatches, symlinks, metadata and truncated media fail closed", async () => {
  const { root, inputs } = await setup();
  try {
    const asset = inputs.corpus.cases.at(-1)!.input.assets[0];
    await Deno.writeFile(join(root, asset.path), new Uint8Array([1, 2, 3]));
    await assertRejects(() => prepareRun(root, source, "offline"));
    assertEquals(await exists(join(root, "runs")), false);
    const first = inputs.corpus.cases[0].input.assets[0],
      original = join(root, first.path),
      renamed = original + ".original";
    await Deno.rename(original, renamed);
    assert(
      (await new Deno.Command("ln", {
        args: ["-s", renamed, original],
        stderr: "null",
      }).output()).success,
    );
    await assertRejects(() =>
      prepareEvidence(root, inputs.corpus.cases[0].input)
    );
    await assertRejects(() => prepareEvidence(root, inputs.corpus.cases[0]));
    const bytes = await Deno.readFile(renamed);
    for (
      const invalid of [
        bytes.slice(0, -1),
        new Uint8Array([...bytes, 1]),
        bytes.toReversed(),
      ]
    ) {
      let failed = false;
      try {
        validateImage(invalid, "image/png");
      } catch {
        failed = true;
      }
      assert(failed);
    }
    const wav = await Deno.readFile(
      join(root, inputs.corpus.cases[2].input.assets[0].path),
    );
    let failed = false;
    try {
      validateWavContainer(wav.slice(0, -1));
    } catch {
      failed = true;
    }
    assert(failed);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
Deno.test("crashes around durable claims never repeat an uncertain invocation", async (t) => {
  for (
    const point of [
      "before_claim",
      "after_claim",
      "after_invoke",
      "after_result",
    ] as const
  ) {
    await t.step(point, async () => {
      const { root, inputs, fixture } = await setup();
      try {
        let calls = 0;
        const offlineOutcome = (
          i: Parameters<typeof fixture>[0],
          a: Parameters<typeof fixture>[1],
        ) => {
          calls++;
          return fixture(i, a);
        };
        await assertRejects(() =>
          executeRun(root, inputs, {
            offlineOutcome,
            checkpoint: (p) => {
              if (p === point) throw new Error("synthetic_crash");
            },
          })
        );
        const after = await executeRun(root, inputs, { offlineOutcome });
        const unknown = point === "after_claim" || point === "after_invoke";
        assertEquals(calls, unknown ? point === "after_claim" ? 0 : 1 : 24);
        assertEquals(after.stopReason, unknown ? "interrupted_attempt" : null);
        if (unknown) {
          assertEquals(
            after.records[0].prediction.outcome,
            "unknown_execution",
          );
          assertEquals(
            after.records.filter((r) => r.prediction.outcome === "unattempted")
              .length,
            23,
          );
        }
        const again = await executeRun(root, inputs, { offlineOutcome });
        assertEquals(again.records, after.records);
      } finally {
        await Deno.remove(root, { recursive: true });
      }
    });
  }
});
Deno.test("racing processes cannot share a run lock; OS releases the lock after the holder exits", async () => {
  const { root } = await setup();
  const worker = join(root, "lock-worker.ts");
  const module =
    new URL("./identification_evaluation/files.ts", import.meta.url).href;
  await Deno.writeTextFile(
    worker,
    `import { withRunLock } from ${
      JSON.stringify(module)
    };\nawait withRunLock(Deno.args[0],async()=>{console.log('locked'); await Deno.stdin.read(new Uint8Array(1));});\n`,
    { mode: 0o600 },
  );
  const child = new Deno.Command("deno", {
    args: [
      "run",
      "--no-config",
      "--no-prompt",
      "--deny-net",
      "--deny-env",
      `--allow-read=${root}`,
      `--allow-write=${root}`,
      worker,
      root,
    ],
    stdin: "piped",
    stdout: "piped",
    stderr: "null",
  }).spawn();
  try {
    const reader = child.stdout.getReader();
    const ready = await reader.read();
    assert(new TextDecoder().decode(ready.value).includes("locked"));
    reader.releaseLock();
    await assertRejects(() => withRunLock(root, () => Promise.resolve(true)));
    child.kill("SIGKILL");
    await child.status;
    assertEquals(await withRunLock(root, () => Promise.resolve(true)), true);
  } finally {
    try {
      child.kill("SIGKILL");
    } catch { /* already exited */ }
    await Deno.remove(root, { recursive: true });
  }
});
Deno.test("call caps and corrupted ledgers cannot turn into extra attempts", async () => {
  const { root, inputs, fixture } = await setup();
  try {
    inputs.manifest.spec.maxCalls = 1;
    let calls = 0;
    const first = await executeRun(root, inputs, {
      offlineOutcome: (i, a) => {
        calls++;
        return fixture(i, a);
      },
    });
    assertEquals(calls, 1);
    assertEquals(first.stopReason, "call_limit");
    await executeRun(root, inputs, {
      offlineOutcome: () => {
        throw new Error("must_not_call");
      },
    });
    const changed = structuredClone(inputs);
    changed.manifest.spec.maxCalls = 2;
    await assertRejects(() =>
      executeRun(root, changed, { offlineOutcome: fixture })
    );
    await Deno.writeTextFile(
      join(first.directory, "claims", `${inputs.manifest.order[0].key}.json`),
      "{",
    );
    await assertRejects(() =>
      executeRun(root, inputs, { offlineOutcome: fixture })
    );
    assertEquals(calls, 1);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
Deno.test("comparison rejects incomplete, source/input/model drift and undeclared profile changes", async () => {
  const { root, inputs, fixture } = await setup();
  try {
    const outcome = (
      i: Parameters<typeof fixture>[0],
      a: Parameters<typeof fixture>[1],
    ) => {
      const r = fixture(i, a);
      return r.kind === "unknown_execution"
        ? { ...r, kind: "refusal" as const }
        : r;
    };
    const result = await executeRun(root, inputs, { offlineOutcome: outcome });
    const { manifest } = result.inputs, rows = result.records;
    const options = {
      leftProfile: "gemini_flash_free" as const,
      rightProfile: "gemini_pro" as const,
      allowProfileDifference: true,
    };
    const comparison = await compareRuns(
      inputs.corpus,
      inputs.taxonomy,
      manifest,
      rows,
      manifest,
      rows,
      options,
    );
    assertEquals(comparison.compatible, true);
    assertEquals(comparison.verdict, "measurement_only");
    await assertRejects(() =>
      compareRuns(
        inputs.corpus,
        inputs.taxonomy,
        manifest,
        rows,
        manifest,
        rows,
        {
          ...options,
          allowProfileDifference: false,
        },
      )
    );
    const badRows = structuredClone(rows);
    badRows[0].returnedModel = "gemini-drift";
    await assertRejects(() =>
      compareRuns(
        inputs.corpus,
        inputs.taxonomy,
        manifest,
        badRows,
        manifest,
        rows,
        options,
      )
    );
    const changed = structuredClone(manifest);
    changed.source.digest = "2".repeat(64);
    const updated = rows.map((r) => ({ ...r, runDigest: "" }));
    const digest = await fingerprintJson(changed);
    updated.forEach((r) => r.runDigest = digest);
    await assertRejects(() =>
      compareRuns(
        inputs.corpus,
        inputs.taxonomy,
        manifest,
        rows,
        changed,
        updated,
        options,
      )
    );
    const changedOrder = structuredClone(manifest);
    changedOrder.spec.orderSeed++;
    changedOrder.order = interleave(
      changedOrder.order,
      changedOrder.spec.orderSeed,
    );
    const orderDigest = await fingerprintJson(changedOrder);
    const reorderedRows = rows.map((r) => ({ ...r, runDigest: orderDigest }));
    // Each run is internally valid; the experimental order differs.
    await generateReport(
      inputs.corpus,
      changedOrder,
      reorderedRows,
      inputs.taxonomy,
    );
    await assertRejects(() =>
      compareRuns(
        inputs.corpus,
        inputs.taxonomy,
        manifest,
        rows,
        changedOrder,
        reorderedRows,
        options,
      )
    );
    const changedTaxonomy = structuredClone(inputs.taxonomy);
    changedTaxonomy.taxa[0].names.push("Changed synonym");
    await assertRejects(() =>
      generateReport(inputs.corpus, manifest, rows, changedTaxonomy)
    );
    const extra = { ...rows[0], private: "raw" };
    await assertRejects(() =>
      generateReport(
        inputs.corpus,
        manifest,
        [extra, ...rows.slice(1)],
        inputs.taxonomy,
      )
    );
    assertEquals(
      (await generateReport(inputs.corpus, manifest, rows, inputs.taxonomy))
        .completeness,
      "complete",
    );
    assertEquals(await readRecords(result.directory, manifest), rows);
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});
Deno.test("repeatability records are scored as separate attempts, never doubled sample size", async () => {
  const { root, inputs } = await setup();
  try {
    const spec = parseRunSpec({
      ...inputs.manifest.spec,
      runId: "repeatability",
      stage: "repeatability",
      repeats: 2,
      maxCalls: 48,
    });
    await atomicJson(join(root, "spec.json"), spec);
    const repeated = await prepareRun(root, source, "offline");
    const fixture = offlineOutcomes(
      await readJson(join(root, "fixtures.json")),
      repeated.corpus,
      spec,
    );
    const result = await executeRun(root, repeated, {
      offlineOutcome: fixture,
    });
    const report = await generateReport(
      repeated.corpus,
      result.inputs.manifest,
      result.records,
      repeated.taxonomy,
    );
    assertEquals(report.slices.length, 28);
    assertEquals(
      report.slices.filter((s) => s.inputGroup === "all_cases").map((s) =>
        s.score.counts.scheduled
      ),
      [12, 12, 12, 12],
    );
  } finally {
    await Deno.remove(root, { recursive: true });
  }
});

Deno.test("offline admission writes private new evidence and refuses upgrades or overwrites", async () => {
  const dir = await Deno.makeTempDir({ dir: scratch, prefix: "comparison-" });
  try {
    const f = fixture();
    const observation = dir + "/observation.jsonl",
      expected = dir + "/expected.json",
      output = dir + "/admitted.json";
    await Deno.writeTextFile(
      observation,
      f.rows.map((r) => JSON.stringify(r)).join("\n") + "\n",
    );
    await Deno.writeTextFile(expected, JSON.stringify(f.expected));
    const args = [
      "--observation",
      observation,
      "--expected",
      expected,
      "--output",
      output,
    ];
    await admitAudioComparisonObservation(args);
    const stored = await Deno.readTextFile(output);
    assertEquals(JSON.parse(stored).accuracyScored, false);
    if (Deno.build.os !== "windows") {
      assertEquals((await Deno.stat(output)).mode! & 0o777, 0o600);
    }
    await assertRejects(() => admitAudioComparisonObservation(args));
    assertEquals(await Deno.readTextFile(output), stored);
    f.rows[0].version = "identification_app_observation_v1";
    await Deno.writeTextFile(
      observation,
      f.rows.map((r) => JSON.stringify(r)).join("\n"),
    );
    await assertRejects(
      () =>
        admitAudioComparisonObservation([
          ...args.slice(0, -1),
          dir + "/excluded.json",
        ]),
      Error,
      "audio_comparison_observation_excluded",
    );
    await assertRejects(
      () => Deno.stat(dir + "/excluded.json"),
      Deno.errors.NotFound,
    );
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("prompt admission writes private new evidence and refuses upgrades or overwrites", async () => {
  const dir = await Deno.makeTempDir({ dir: scratch, prefix: "comparison-" });
  try {
    const f = promptFixture();
    const observation = dir + "/observation.jsonl",
      expected = dir + "/expected.json",
      output = dir + "/admitted.json";
    await Deno.writeTextFile(
      observation,
      f.rows.map((r) => JSON.stringify(r)).join("\n") + "\n",
    );
    await Deno.writeTextFile(expected, JSON.stringify(f.expected));
    const args = [
      "--observation",
      observation,
      "--expected",
      expected,
      "--output",
      output,
    ];
    await admitAudioPromptComparisonObservation(args);
    const stored = await Deno.readTextFile(output);
    assertEquals(JSON.parse(stored).accuracyScored, false);
    if (Deno.build.os !== "windows") {
      assertEquals((await Deno.stat(output)).mode! & 0o777, 0o600);
    }
    await assertRejects(() => admitAudioPromptComparisonObservation(args));
    assertEquals(await Deno.readTextFile(output), stored);
    f.rows[0].version = "identification_app_observation_v1";
    await Deno.writeTextFile(
      observation,
      f.rows.map((r) => JSON.stringify(r)).join("\n"),
    );
    await assertRejects(
      () =>
        admitAudioPromptComparisonObservation([
          ...args.slice(0, -1),
          dir + "/excluded.json",
        ]),
      Error,
      "audio_prompt_comparison_observation_excluded",
    );
    await assertRejects(
      () => Deno.stat(dir + "/excluded.json"),
      Deno.errors.NotFound,
    );
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
