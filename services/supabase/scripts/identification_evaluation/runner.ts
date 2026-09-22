import { join } from "node:path";
import type {
  AIProviderOutcome,
  MultimodalAIRequest,
  PreparedAIExecution,
} from "../../functions/_shared/ai/contracts.ts";
import {
  assertOfflinePermissions,
  liveCredential,
  validateLiveApproval,
  validateSelection,
} from "./admission.ts";
import { prepareEvidence } from "./assets.ts";
import { type EvaluationInput, SCORER_VERSION } from "./contracts.ts";
import { parseRunCorpus, type RunCorpus } from "./exploratory.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  atomicJson,
  claimJson,
  exists,
  privateDirectory,
  readJson,
  withRunLock,
} from "./files.ts";
import { assignmentFor, fixtureAuthority, interleave } from "./profiles.ts";
import { emptyRecord, projectOutcome } from "./projection.ts";
import {
  type Assignment,
  type AttemptRecord,
  BOUNDARY,
  parseAttempt,
  parseClaim,
  parseManifest,
  parseRunSpec,
  parseTaxonomy,
  type Pricing,
  type Readiness,
  RUN_VERSION,
  type RunManifest,
  type SourceIdentity,
  type Taxonomy,
} from "./runContracts.ts";
import { requireCondition as check } from "./validation.ts";

export interface EvaluationInputs {
  corpus: RunCorpus;
  taxonomy: Taxonomy;
  manifest: RunManifest;
}
export async function prepareRun(
  root: string,
  source: SourceIdentity,
  mode: "offline" | "live",
  now = Date.now(),
): Promise<EvaluationInputs> {
  const corpus = parseRunCorpus(
    await readJson(join(root, "corpus.json")),
  );
  const taxonomy = parseTaxonomy(
    await readJson(join(root, "taxonomy.json"), 32 * 1024 * 1024),
  );
  const spec = parseRunSpec(await readJson(join(root, "spec.json")));
  check(spec.mode === mode);
  await validateSelection(corpus, spec, taxonomy);
  let pricing: Pricing | null = null, readiness: Readiness | null = null;
  if (mode === "live") {
    const credential = await liveCredential();
    ({ pricing, readiness } = await validateLiveApproval(
      corpus,
      spec,
      await readJson(join(root, "pricing.json")),
      await readJson(join(root, "readiness.json")),
      credential,
      now,
    ));
  } else await assertOfflinePermissions();
  const assignments: Assignment[] = [];
  // Preflight ALL selected evidence before preparing even the first execution.
  // Keep only hashes/settings, then reload one bounded case at dispatch time.
  for (
    const item of corpus.cases.filter((c) =>
      spec.caseIds.includes(c.input.caseId)
    )
  ) {
    const request = await prepareEvidence(root, item.input);
    for (let attempt = 1; attempt <= spec.repeats; attempt++) {
      for (const profile of spec.profiles) {
        assignments.push(
          await assignmentFor(item.input, request, profile, attempt, pricing),
        );
      }
    }
  }
  const manifest = parseManifest({
    version: RUN_VERSION,
    boundary: BOUNDARY,
    createdAt: new Date(now).toISOString(),
    spec,
    source,
    scorerVersion: SCORER_VERSION,
    taxonomyVersion: taxonomy.taxonomyVersion,
    preparationVersion: corpus.preparationVersion,
    pricing,
    processor: readiness
      ? {
        projectRef: readiness.projectRef,
        credentialRef: readiness.credentialRef,
      }
      : null,
    order: interleave(assignments, spec.orderSeed),
  });
  return { corpus, taxonomy, manifest };
}

export function validateRecord(
  recordValue: unknown,
  assignment: Assignment,
  runDigest: string,
  pricing: Pricing | null,
): AttemptRecord {
  const r = parseAttempt(recordValue);
  check(
    r.key === assignment.key && r.runDigest === runDigest &&
      r.prediction.caseId === assignment.caseId &&
      r.prediction.outcome !== "unattempted",
  );
  if (
    pricing && r.reason !== "model_mismatch" &&
    !["unknown_execution", "operational_failure"].includes(r.prediction.outcome)
  ) check(r.returnedModel === assignment.model);
  if (!pricing) check(r.estimatedUpperUsd === null);
  return r;
}
/** Read the durable ledger, synthesizing unattempted/uncertain entries without
 * ever treating missing/torn results as permission to repeat a started call.
 */
export async function readRecords(
  directory: string,
  manifestValue: unknown,
): Promise<AttemptRecord[]> {
  const manifest = parseManifest(manifestValue),
    digest = await fingerprintJson(manifest),
    rows: AttemptRecord[] = [];
  let gap = false;
  for (const a of manifest.order) {
    const claimPath = join(directory, "claims", `${a.key}.json`),
      resultPath = join(directory, "results", `${a.key}.json`);
    const started = await exists(claimPath), result = await exists(resultPath);
    check(!result || started);
    if (!started) {
      gap = true;
      rows.push(emptyRecord(a, digest));
      continue;
    }
    check(!gap);
    parseClaim(await readJson(claimPath, 4096), a, digest);
    rows.push(
      result
        ? validateRecord(
          await readJson(resultPath, 32768),
          a,
          digest,
          manifest.pricing,
        )
        : emptyRecord(a, digest, "interrupted_attempt"),
    );
  }
  return rows;
}
function stopAfter(record: AttemptRecord, live: boolean): boolean {
  return record.reason === "interrupted_attempt" || live && (
        ["unknown_execution", "operational_failure"].includes(
          record.prediction.outcome,
        ) ||
        record.reason === "model_mismatch" || record.estimatedUpperUsd === null
      );
}
export interface RunnerDependencies {
  // Testing only. CLI live composition is fixed; no user adapter/endpoint flag.
  prepare?: (
    request: MultimodalAIRequest,
    assignment: Assignment,
  ) => PreparedAIExecution;
  offlineOutcome?: (
    input: EvaluationInput,
    assignment: Assignment,
  ) => AIProviderOutcome;
  // Crash injection before/after commitment proves resume behavior.
  checkpoint?: (
    point: "before_claim" | "after_claim" | "after_invoke" | "after_result",
  ) => void;
}
export interface RunResult {
  directory: string;
  inputs: EvaluationInputs;
  records: AttemptRecord[];
  stopReason: string | null;
}

export function guardNextAttempt(
  records: AttemptRecord[],
  maxCalls: number,
  budgetUsd: number,
  reservedUsd: number,
  live: boolean,
): "call_limit" | "budget_exceeded" | "usage_missing" | null {
  const started = records.filter((r) => r.prediction.outcome !== "unattempted");
  if (started.length >= maxCalls) return "call_limit";
  if (!live) return null;
  if (started.some((r) => r.estimatedUpperUsd === null)) return "usage_missing";
  const spent = started.reduce((n, r) => n + r.estimatedUpperUsd!, 0);
  return spent + reservedUsd > budgetUsd ? "budget_exceeded" : null;
}

export async function executeRun(
  root: string,
  inputs: EvaluationInputs,
  dependencies: RunnerDependencies = {},
): Promise<RunResult> {
  if (
    inputs.manifest.spec.mode === "live" &&
    (Object.keys(dependencies).length > 0 || dependencies.prepare ||
      dependencies.offlineOutcome || dependencies.checkpoint)
  ) throw new Error("evaluation_live_dependencies_forbidden");
  parseManifest(inputs.manifest);
  await validateSelection(inputs.corpus, inputs.manifest.spec, inputs.taxonomy);
  const runs = await privateDirectory(join(root, "runs"));
  const directory = await privateDirectory(
    join(runs, inputs.manifest.spec.runId),
  );
  return await withRunLock(directory, async () => {
    await privateDirectory(join(directory, "claims"));
    await privateDirectory(join(directory, "results"));
    const manifestPath = join(directory, "manifest.json");
    let manifest = inputs.manifest;
    if (await exists(manifestPath)) {
      const previous = parseManifest(await readJson(manifestPath));
      check(
        await fingerprintJson({
          ...manifest,
          createdAt: previous.createdAt,
        }) === await fingerprintJson(previous),
      );
      manifest = previous;
    } else await atomicJson(manifestPath, manifest);
    const runDigest = await fingerprintJson(manifest),
      records = await readRecords(directory, manifest);
    const live = manifest.spec.mode === "live";
    // Revalidate bindings and the actual credential before every live dispatch,
    // including resumed runs. The readiness record is never copied to artifacts.
    const approve = async () => {
      const key = await liveCredential();
      await validateLiveApproval(
        inputs.corpus,
        manifest.spec,
        await readJson(join(root, "pricing.json")),
        await readJson(join(root, "readiness.json")),
        key,
        Date.now(),
      );
    };
    if (!live) {
      await assertOfflinePermissions();
      check(dependencies.offlineOutcome || dependencies.prepare);
    }
    let stopReason: string | null = null;
    for (let i = 0; i < records.length; i++) {
      const a = manifest.order[i];
      if (records[i].prediction.outcome !== "unattempted") {
        if (records[i].reason === "interrupted_attempt") {
          await atomicJson(
            join(directory, "results", `${a.key}.json`),
            records[i],
          );
        }
        if (stopAfter(records[i], live)) {
          stopReason = records[i].reason;
          break;
        }
        continue;
      }
      stopReason = guardNextAttempt(
        records,
        manifest.spec.maxCalls,
        manifest.spec.budgetUsd,
        a.reservedUsd,
        live,
      );
      if (stopReason) break;
      const input = inputs.corpus.cases.find((c) =>
        c.input.caseId === a.caseId
      )!.input;
      const request = await prepareEvidence(root, input);
      check(
        await fingerprintJson(
          await assignmentFor(
            input,
            request,
            a.profile,
            a.attempt,
            manifest.pricing,
          ),
        ) === await fingerprintJson(a),
      );
      if (live) await approve();
      const execution = dependencies.prepare?.(request, a) ?? (live
        ? (await import("../../functions/_shared/ai/production.ts"))
          .prepareAIExecution(request, fixtureAuthority(a.profile))
        : null);
      if (execution) {
        check(await fingerprintJson(execution.snapshot) === a.policyDigest);
      }
      dependencies.checkpoint?.("before_claim");
      await claimJson(
        join(directory, "claims", `${a.key}.json`),
        parseClaim(
          {
            version: "evaluation_started_v1",
            runDigest,
            key: a.key,
            requestDigest: a.requestDigest,
            reservedUsd: a.reservedUsd,
            startedAt: new Date().toISOString(),
          },
          a,
          runDigest,
        ),
      );
      dependencies.checkpoint?.("after_claim");
      let record: AttemptRecord;
      try {
        const outcome = execution
          ? await execution.invoke()
          : dependencies.offlineOutcome!(input, a);
        record = projectOutcome(
          outcome,
          input,
          a,
          runDigest,
          inputs.taxonomy,
          manifest.pricing,
        );
      } catch {
        record = emptyRecord(a, runDigest, "interrupted_attempt");
      }
      dependencies.checkpoint?.("after_invoke");
      await atomicJson(join(directory, "results", `${a.key}.json`), record);
      records[i] = record;
      dependencies.checkpoint?.("after_result");
      if (stopAfter(record, live)) {
        stopReason = record.reason;
        break;
      }
    }
    if (stopReason === "budget_exceeded" || stopReason === "call_limit") {
      for (let i = 0; i < records.length; i++) {
        if (records[i].prediction.outcome === "unattempted") {
          records[i] = emptyRecord(manifest.order[i], runDigest, stopReason);
        }
      }
    }
    return { directory, inputs: { ...inputs, manifest }, records, stopReason };
  });
}
