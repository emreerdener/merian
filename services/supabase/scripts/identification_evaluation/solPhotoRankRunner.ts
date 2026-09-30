/** Fixed Sol-only experiment. Durable claims are never retried or inherited. */
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  AIProviderOutcome,
  MultimodalAIRequest,
} from "../../functions/_shared/ai/contracts.ts";
import { createAIExecution } from "../../functions/_shared/ai/execution.ts";
import {
  createOpenAIPhotoModelEvaluationAdapter,
  createOpenAISolRankEvaluationAdapter,
} from "../../functions/_shared/ai/openai.ts";
import { openAIPhotoModelSnapshot } from "../../functions/_shared/ai/openaiPhotoModels.ts";
import { assertOfflinePermissions, liveCredential } from "./admission.ts";
import { prepareEvidence } from "./assets.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  parseRatings,
  type Ratings,
  RUBRIC,
  unavailableRatings,
} from "./explanationContracts.ts";
import {
  assertPrivateReviewReady,
  type ReviewDisplay,
} from "./explanationView.ts";
import { reviewExplanation } from "./explanationReview.ts";
import {
  atomicJson,
  claimJson,
  exists,
  privateDirectory,
  readJson,
  sourceIdentity,
  withRunLock,
} from "./files.ts";
import {
  parsePhotoModelMeasurementRecord,
  PHOTO_MODEL_BILLING_MULTIPLIER,
  photoModelCostUpper,
  type PhotoModelMeasurementRecord,
  projectMeasuredPhotoModelOutcome,
} from "./photoModelRecords.ts";
import { type SourceIdentity, timestamp } from "./runContracts.ts";
import { validateSolRankApproval } from "./solPhotoRankAdmission.ts";
import {
  SOL_RANK_PROFILE,
  solPhotoRankSnapshot,
} from "./solPhotoRankCandidate.ts";
import {
  loadSolRankPacket,
  solBillingAssignment,
  type SolRankAssignment,
  solRankRequest,
} from "./solPhotoRankLivePreparation.ts";
import {
  type SolRankEntry,
  solRankScreenDecision,
  solRankSummary,
} from "./solPhotoRankScoring.ts";
import { fields, member, requireCondition as check } from "./validation.ts";

const STOP_REASONS = [
  "interrupted_attempt",
  "provider_failure",
  "review_missing",
  "screen_failed",
  "screen_unassessable",
  "budget_exhausted",
  "configuration_invalid",
] as const;
type StopReason = typeof STOP_REASONS[number];
interface OfflineDependencies {
  outcome: (
    assignment: SolRankAssignment,
    request: MultimodalAIRequest,
  ) => Promise<AIProviderOutcome>;
  review: (display: ReviewDisplay | null) => Promise<Ratings | null>;
}
const filename = (ordinal: number) =>
  String(ordinal).padStart(2, "0") + ".json";
const reserve = (a: SolRankAssignment) =>
  Math.ceil(a.reservedNanoUsd * 11 / 10);
async function onlyEntries(path: string, allowed: string[]) {
  for await (const e of Deno.readDir(path)) {
    check(e.isFile && !e.isSymlink && allowed.includes(e.name));
  }
}
async function configurationStop(directory: string) {
  const manifest = fields(await readJson(join(directory, "manifest.json")), [
    "version",
    "createdAt",
    "binding",
  ]);
  check(manifest.version === "sol_photo_rank_run_v1");
  timestamp(manifest.createdAt);
  const runDigest = await fingerprintJson(manifest),
    stopPath = join(directory, "stop.json");
  let reason: StopReason = "configuration_invalid";
  if (await exists(stopPath)) {
    const v = fields(await readJson(stopPath), [
      "version",
      "runDigest",
      "reason",
    ]);
    check(v.version === "sol_photo_rank_stop_v1" && v.runDigest === runDigest);
    member(v.reason, STOP_REASONS);
    reason = v.reason;
  } else {await claimJson(stopPath, {
      version: "sol_photo_rank_stop_v1",
      runDigest,
      reason,
    });}
  const state = {
    version: "sol_photo_rank_state_v1",
    runDigest,
    stop: reason,
    claimedCalls: null,
    completedCalls: null,
    heldReservationUsd: null,
    complete: false,
    evidenceStatus: "unverified_existing_run",
    productionActivationAuthorized: false,
  };
  await atomicJson(join(directory, "state.json"), state);
  return state;
}
export async function executeSolRankComparison(
  root: string,
  source: SourceIdentity,
  mode: "offline" | "live",
  dependencies?: OfflineDependencies,
) {
  const live = mode === "live";
  check(live ? dependencies === undefined : dependencies !== undefined);
  if (!live) await assertOfflinePermissions();
  const repository = fileURLToPath(new URL("../../../../", import.meta.url));
  const load = async () => {
    if (live) {
      check(
        await fingerprintJson(await sourceIdentity(repository)) ===
          await fingerprintJson(source),
      );
    }
    const packet = await loadSolRankPacket(root, source);
    check(packet.corpus.evidenceOrigin === (live ? "real" : "synthetic"));
    let credential = "", approval = null;
    if (live) {
      credential = await liveCredential("openai");
      await assertPrivateReviewReady();
      approval = await validateSolRankApproval(
        await readJson(join(root, "sol-rank-approval.json")),
        packet,
        credential,
        Date.now(),
      );
    }
    const reservedNanoUsd = packet.report.order.reduce(
      (n, a) => n + reserve(a),
      0,
    );
    check(reservedNanoUsd <= Math.floor(packet.plan.budgetUsd * 1e9));
    const binding = {
      version: "sol_photo_rank_run_binding_v2",
      recordVersion: "photo_model_attempt_v2",
      summaryVersion: "sol_photo_rank_summary_v2",
      screeningPolicy: packet.plan.screeningPolicy,
      mode,
      source,
      planDigest: packet.report.planDigest,
      preparationDigest: packet.plan.preparationDigest,
      referenceReviewDigest: packet.plan.referenceReviewDigest,
      order: packet.report.order,
      budgetUsd: packet.plan.budgetUsd,
      reservedNanoUsd,
      billingMultiplier: PHOTO_MODEL_BILLING_MULTIPLIER,
      approvalDigest: approval ? await fingerprintJson(approval) : null,
      rubricDigest: await fingerprintJson(RUBRIC),
      reviewerRef: approval?.reviewerRef ?? "synthetic-reviewer",
      delegationRef: approval?.delegationRef ?? "synthetic-delegation",
    };
    return { packet, credential, binding };
  };
  const runPath = join(root, "sol-photo-rank-run");
  // Reject fresh invalid starts without creating execution authority. Revalidate under the lock.
  if (!await exists(join(runPath, "manifest.json"))) await load();
  const directory = await privateDirectory(runPath);
  return await withRunLock(directory, async () => {
    const manifestPath = join(directory, "manifest.json");
    if (await exists(manifestPath)) {
      const previous = fields(await readJson(manifestPath), [
        "version",
        "createdAt",
        "binding",
      ]);
      check(
        previous.version === "sol_photo_rank_run_v1",
        "unsupported_version",
      );
      timestamp(previous.createdAt);
      const binding = previous.binding;
      // Refuse historical formats before admission can write a configuration stop.
      // Their accounting and evidence must remain intact even after inputs expire.
      check(
        binding !== null && typeof binding === "object" &&
          !Array.isArray(binding) && "version" in binding &&
          binding.version === "sol_photo_rank_run_binding_v2",
        "unsupported_version",
      );
    }
    let initial: Awaited<ReturnType<typeof load>>;
    try {
      initial = await load();
    } catch (error) {
      if (await exists(join(directory, "manifest.json"))) {
        return await configurationStop(directory);
      }
      throw error;
    }
    for await (const e of Deno.readDir(directory)) {
      check(
        [
          ".lock",
          "manifest.json",
          "claims",
          "results",
          "reviews",
          "state.json",
          "summary.json",
          "stop.json",
        ].includes(e.name) && !e.isSymlink,
      );
    }
    for (const name of ["claims", "results", "reviews"]) {
      await privateDirectory(join(directory, name));
    }
    if (!await exists(manifestPath)) {
      for (const name of ["claims", "results", "reviews"]) {
        await onlyEntries(join(directory, name), []);
      }
      check(
        !await exists(join(directory, "stop.json")) &&
          !await exists(join(directory, "summary.json")),
      );
      await claimJson(manifestPath, {
        version: "sol_photo_rank_run_v1",
        createdAt: new Date().toISOString(),
        binding: initial.binding,
      });
    }
    const manifest = fields(await readJson(manifestPath), [
      "version",
      "createdAt",
      "binding",
    ]);
    check(manifest.version === "sol_photo_rank_run_v1");
    timestamp(manifest.createdAt);
    if (
      await fingerprintJson(manifest.binding) !==
        await fingerprintJson(initial.binding)
    ) {
      return await configurationStop(directory);
    }
    const runDigest = await fingerprintJson(manifest), packet = initial.packet;
    const names = packet.report.order.map((a) => filename(a.ordinal));
    for (const name of ["claims", "results", "reviews"]) {
      await onlyEntries(join(directory, name), names);
    }
    const entries = new Map<number, SolRankEntry>();
    const records = new Map<number, PhotoModelMeasurementRecord>();
    let stop: StopReason | null = null, claimed = 0, heldNanoUsd = 0;
    const stopPath = join(directory, "stop.json");
    if (await exists(stopPath)) {
      const v = fields(await readJson(stopPath), [
        "version",
        "runDigest",
        "reason",
      ]);
      check(
        v.version === "sol_photo_rank_stop_v1" && v.runDigest === runDigest,
      );
      member(v.reason, STOP_REASONS);
      stop = v.reason;
    }
    const screensPassed = () =>
      packet.report.order.filter((a) => a.phase === "screen").every((a) =>
        entries.has(a.ordinal) &&
        solRankScreenDecision(packet, a, entries.get(a.ordinal)!) === "pass"
      );
    const reconcile = async () => {
      entries.clear();
      records.clear();
      claimed = 0;
      heldNanoUsd = 0;
      let gap = false;
      for (const a of packet.report.order) {
        const name = filename(a.ordinal),
          assignmentDigest = await fingerprintJson(a);
        const claimPath = join(directory, "claims", name),
          resultPath = join(directory, "results", name),
          reviewPath = join(directory, "reviews", name);
        if (!await exists(claimPath)) {
          check(!await exists(resultPath) && !await exists(reviewPath));
          gap = true;
          continue;
        }
        check(!gap);
        const c = fields(await readJson(claimPath), [
          "version",
          "runDigest",
          "ordinal",
          "assignmentDigest",
          "reservedNanoUsd",
          "startedAt",
        ]);
        check(
          c.version === "sol_photo_rank_claim_v1" &&
            c.runDigest === runDigest &&
            c.ordinal === a.ordinal &&
            c.assignmentDigest === assignmentDigest &&
            c.reservedNanoUsd === reserve(a),
        );
        timestamp(c.startedAt);
        claimed++;
        heldNanoUsd += reserve(a);
        if (!await exists(resultPath)) {
          stop ??= "interrupted_attempt";
          gap = true;
          check(!await exists(reviewPath));
          continue;
        }
        const billing = solBillingAssignment(a);
        const record = parsePhotoModelMeasurementRecord(
          await readJson(resultPath),
          billing,
          runDigest,
          assignmentDigest,
        );
        const expectedCost =
          record.returnedModel === a.model && record.serviceTier === "default"
            ? photoModelCostUpper(record.usage, billing, packet.pricing)
            : null;
        check(
          record.estimatedUpperNanoUsd === expectedCost &&
            (expectedCost === null || expectedCost <= reserve(a)),
        );
        records.set(a.ordinal, record);
        if (record.reason !== "completed") {
          stop ??= "provider_failure";
          gap = true;
          check(!await exists(reviewPath));
          continue;
        }
        if (!await exists(reviewPath)) {
          stop ??= "review_missing";
          gap = true;
          continue;
        }
        const r = fields(await readJson(reviewPath), [
          "version",
          "runDigest",
          "ordinal",
          "resultDigest",
          "factsDigest",
          "rubricDigest",
          "method",
          "reviewerRef",
          "delegationRef",
          "ratings",
        ]);
        check(
          r.version === "sol_photo_rank_review_v1" &&
            r.runDigest === runDigest && r.ordinal === a.ordinal &&
            r.resultDigest === await fingerprintJson(record) &&
            r.factsDigest === a.factsDigest &&
            r.rubricDigest === initial.binding.rubricDigest &&
            r.method === "assistant_local_v1" &&
            r.reviewerRef === initial.binding.reviewerRef &&
            r.delegationRef === initial.binding.delegationRef,
        );
        const entry = { record, ratings: parseRatings(r.ratings) };
        entries.set(a.ordinal, entry);
        if (
          Object.values(entry.ratings).some((r) =>
            r.reason === "review_unavailable"
          )
        ) {
          stop ??= "review_missing";
          gap = true;
        }
        if (a.phase === "screen") {
          const decision = solRankScreenDecision(packet, a, entry);
          if (decision !== "pass") {
            stop ??= decision === "failed"
              ? "screen_failed"
              : "screen_unassessable";
            gap = true;
          }
        } else check(screensPassed());
      }
    };
    const saveState = async () => {
      if (stop && !await exists(stopPath)) {
        await claimJson(stopPath, {
          version: "sol_photo_rank_stop_v1",
          runDigest,
          reason: stop,
        });
      }
      const state = {
        version: "sol_photo_rank_state_v1",
        runDigest,
        stop,
        screeningPolicy: packet.plan.screeningPolicy,
        claimedCalls: claimed,
        completedCalls: entries.size,
        heldReservationUsd: heldNanoUsd / 1e9,
        complete: claimed === 18 && entries.size === 18 && stop === null,
        evidenceStatus: packet.report.evidenceStatus,
        productionActivationAuthorized: false,
      };
      await atomicJson(join(directory, "summary.json"), {
        ...solRankSummary(packet, entries, records),
        runDigest,
        complete: state.complete,
        stop,
      });
      await atomicJson(join(directory, "state.json"), state);
      return state;
    };
    await reconcile();
    if (stop) return await saveState();
    for (const a of packet.report.order) {
      if (entries.has(a.ordinal)) continue;
      check(claimed < packet.plan.maxCalls);
      if (heldNanoUsd + reserve(a) > Math.floor(packet.plan.budgetUsd * 1e9)) {
        stop = "budget_exhausted";
        break;
      }
      if (a.phase === "challenge") check(screensPassed());
      const prepareCall = async () => {
        const current = await load();
        check(
          await fingerprintJson(current.binding) ===
            await fingerprintJson(initial.binding),
        );
        const input = current.packet.corpus.cases.find((c) =>
          c.input.caseId === a.caseId
        )!.input;
        const request = await prepareEvidence(root, input);
        const candidate = a.profile === SOL_RANK_PROFILE;
        const { snapshot, parameters } = solRankRequest(request, candidate);
        check(
          await fingerprintJson(snapshot) === a.snapshotDigest &&
            await fingerprintJson(parameters) === a.requestDigest,
        );
        const execution = !live ? null : candidate
          ? createAIExecution(
            createOpenAISolRankEvaluationAdapter(current.credential),
            request,
            solPhotoRankSnapshot(request),
          )
          : createAIExecution(
            createOpenAIPhotoModelEvaluationAdapter(current.credential),
            request,
            openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
          );
        return { current, input, request, execution };
      };
      let call: Awaited<ReturnType<typeof prepareCall>>;
      try {
        call = await prepareCall();
      } catch {
        stop = "configuration_invalid";
        break;
      }
      const { current, input, request, execution } = call;
      const assignmentDigest = await fingerprintJson(a),
        name = filename(a.ordinal);
      await claimJson(join(directory, "claims", name), {
        version: "sol_photo_rank_claim_v1",
        runDigest,
        ordinal: a.ordinal,
        assignmentDigest,
        reservedNanoUsd: reserve(a),
        startedAt: new Date().toISOString(),
      });
      let outcome: AIProviderOutcome;
      try {
        outcome = execution
          ? await execution.invoke()
          : await dependencies!.outcome(a, request);
      } catch {
        outcome = {
          kind: "unknown_execution",
          providerDurationMs: 0,
          providerCompletedAt: Date.now(),
          returnedModel: null,
          usage: null,
          finishReason: null,
          responseCharacters: 0,
        };
      }
      const card = current.packet.facts.cards.find((c) =>
        c.caseId === a.caseId
      )!;
      const { record, display } = projectMeasuredPhotoModelOutcome(
        outcome,
        input,
        request,
        card,
        solBillingAssignment(a),
        runDigest,
        assignmentDigest,
        current.packet.taxonomy,
        current.packet.pricing,
      );
      await claimJson(join(directory, "results", name), record);
      if (record.reason === "completed") {
        const ratings = live
          ? await reviewExplanation(display, 600000, true)
          : await dependencies!.review(display);
        await claimJson(join(directory, "reviews", name), {
          version: "sol_photo_rank_review_v1",
          runDigest,
          ordinal: a.ordinal,
          resultDigest: await fingerprintJson(record),
          factsDigest: a.factsDigest,
          rubricDigest: initial.binding.rubricDigest,
          method: "assistant_local_v1",
          reviewerRef: initial.binding.reviewerRef,
          delegationRef: initial.binding.delegationRef,
          ratings: parseRatings(ratings ?? unavailableRatings()),
        });
      }
      await reconcile();
      await saveState();
      if (stop) break;
    }
    return await saveState();
  });
}
