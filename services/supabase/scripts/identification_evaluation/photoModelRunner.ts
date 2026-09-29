/** Bounded scripts-only runner. A durable claim is never retried, even after a crash. */
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  AIProviderOutcome,
  MultimodalAIRequest,
} from "../../functions/_shared/ai/contracts.ts";
import { createAIExecution } from "../../functions/_shared/ai/execution.ts";
import { createOpenAIPhotoModelEvaluationAdapter } from "../../functions/_shared/ai/openai.ts";
import {
  buildOpenAIPhotoModelRequestParameters,
  openAIPhotoModelSnapshot,
} from "../../functions/_shared/ai/openaiPhotoModels.ts";
import { assertOfflinePermissions, liveCredential } from "./admission.ts";
import { prepareEvidence } from "./assets.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  parseRatings,
  type Ratings,
  ratingsPass,
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
  PHOTO_MODEL_REFERENCE_GAP_POLICY,
  validatePhotoModelApproval,
} from "./photoModelAdmission.ts";
import {
  loadPhotoModelParent,
  type PhotoModelEntry as Entry,
  photoModelScreenPass as screenPass,
} from "./photoModelContinuation.ts";
import {
  loadPhotoModelPacket,
  type PhotoModelAssignment,
} from "./photoModelPreparation.ts";
import {
  parsePhotoModelRecord,
  PHOTO_MODEL_BILLING_MULTIPLIER,
  photoModelCostUpper,
  projectPhotoModelOutcome,
} from "./photoModelRecords.ts";
import { type SourceIdentity, timestamp } from "./runContracts.ts";
import { fields, member, requireCondition as check } from "./validation.ts";

const STOP_REASONS = [
  "interrupted_attempt",
  "provider_failure",
  "review_missing",
  "screen_failed",
  "budget_exhausted",
  "configuration_invalid",
] as const;
type StopReason = typeof STOP_REASONS[number];
interface OfflineDependencies {
  outcome: (
    assignment: PhotoModelAssignment,
    request: MultimodalAIRequest,
  ) => Promise<AIProviderOutcome>;
  review: (display: ReviewDisplay | null) => Promise<Ratings | null>;
}
const filename = (ordinal: number) =>
  String(ordinal).padStart(2, "0") + ".json";
const reserve = (a: PhotoModelAssignment) =>
  Math.ceil(a.reservedNanoUsd * 11 / 10);
async function onlyEntries(path: string, allowed: string[]) {
  for await (const e of Deno.readDir(path)) {
    check(e.isFile && !e.isSymlink && allowed.includes(e.name));
  }
}
/** Existing runs retain a terminal stop even when their original inputs no longer validate. */
async function configurationStop(directory: string) {
  const manifest = fields(await readJson(join(directory, "manifest.json")), [
    "version",
    "createdAt",
    "binding",
  ]);
  check(
    manifest.version === "photo_model_run_v1" ||
      manifest.version === "photo_model_run_v2",
  );
  timestamp(manifest.createdAt);
  const runDigest = await fingerprintJson(manifest),
    stopPath = join(directory, "stop.json");
  let reason: StopReason = "configuration_invalid";
  if (await exists(stopPath)) {
    const existing = fields(await readJson(stopPath), [
      "version",
      "runDigest",
      "reason",
    ]);
    check(
      existing.version === "photo_model_stop_v1" &&
        existing.runDigest === runDigest,
    );
    member(existing.reason, STOP_REASONS);
    reason = existing.reason;
  } else {await claimJson(stopPath, {
      version: "photo_model_stop_v1",
      runDigest,
      reason,
    });}
  // The original packet cannot be validated. Retain the journal; never guess its totals.
  const state = {
    version: manifest.version === "photo_model_run_v2"
      ? "photo_model_state_v2"
      : "photo_model_state_v1",
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

export async function executePhotoModelComparison(
  root: string,
  source: SourceIdentity,
  mode: "offline" | "live",
  dependencies?: OfflineDependencies,
) {
  return await executePhotoModelRun(root, source, mode, dependencies, false);
}

export async function executePhotoModelContinuation(
  root: string,
  source: SourceIdentity,
  mode: "offline" | "live",
  dependencies?: OfflineDependencies,
) {
  try {
    check(await exists(join(root, "photo-model-run")));
    await privateDirectory(join(root, "photo-model-run"));
    const lock = await Deno.lstat(join(root, "photo-model-run", ".lock"));
    check(lock.isFile && !lock.isSymlink && lock.nlink === 1);
  } catch (error) {
    const continuationPath = join(root, "photo-model-continuation");
    if (!await exists(join(continuationPath, "manifest.json"))) throw error;
    const directory = await privateDirectory(continuationPath);
    return await withRunLock(directory, () => configurationStop(directory));
  }
  return await withRunLock(
    join(root, "photo-model-run"),
    () => executePhotoModelRun(root, source, mode, dependencies, true),
  );
}

async function executePhotoModelRun(
  root: string,
  source: SourceIdentity,
  mode: "offline" | "live",
  dependencies: OfflineDependencies | undefined,
  continuation: boolean,
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
    const packet = await loadPhotoModelPacket(root, source);
    check(
      live
        ? packet.corpus.evidenceOrigin === "real"
        : packet.corpus.evidenceOrigin === "synthetic",
    );
    let credential = "", approval = null;
    if (live) credential = await liveCredential("openai");
    const parent = continuation
      ? await loadPhotoModelParent(
        root,
        packet,
        mode,
        live ? credential : undefined,
      )
      : null;
    if (live) {
      await assertPrivateReviewReady();
      approval = await validatePhotoModelApproval(
        await readJson(
          join(
            root,
            continuation
              ? "photo-model-continuation-approval.json"
              : "photo-model-approval.json",
          ),
        ),
        packet,
        credential,
        Date.now(),
        parent ?? undefined,
      );
      if (parent) {
        check(Date.parse(approval.approvedAt) >= Date.parse(parent.startedAt));
      }
    }
    const reservedNanoUsd = packet.report.order.reduce(
      (n, a) => n + reserve(a),
      0,
    );
    // Freeze the entire schedule before even the first screening call.
    check(reservedNanoUsd <= Math.floor(packet.plan.budgetUsd * 1e9));
    const binding = {
      version: continuation
        ? "photo_model_run_binding_v2"
        : "photo_model_run_binding_v1",
      ...(parent
        ? {
          continuation: {
            parentRunDigest: parent.parentRunDigest,
            parentArtifactsDigest: parent.parentArtifactsDigest,
            inheritedOrdinals: [1],
            maxAdditionalCalls: 17,
            screeningPolicy: PHOTO_MODEL_REFERENCE_GAP_POLICY,
          },
        }
        : {}),
      mode,
      source,
      planDigest: packet.report.planDigest,
      order: packet.report.order,
      budgetUsd: packet.plan.budgetUsd,
      reservedNanoUsd,
      billingMultiplier: PHOTO_MODEL_BILLING_MULTIPLIER,
      approvalDigest: approval ? await fingerprintJson(approval) : null,
      rubricDigest: await fingerprintJson(RUBRIC),
      reviewerRef: approval?.reviewerRef ?? "synthetic-reviewer",
      delegationRef: approval?.delegationRef ?? "synthetic-delegation",
    };
    return { packet, credential, binding, parent };
  };
  const runPath = join(
    root,
    continuation ? "photo-model-continuation" : "photo-model-run",
  );
  // Initial admission failures must remain artifact-free. Existing runs validate under their lock.
  const first = await exists(join(runPath, "manifest.json"))
    ? null
    : await load();
  const directory = await privateDirectory(runPath);
  return await withRunLock(directory, async () => {
    let initial: Awaited<ReturnType<typeof load>>;
    try {
      initial = first ?? await load();
    } catch {
      return await configurationStop(directory);
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
          "stop.json",
        ].includes(e.name) && !e.isSymlink,
      );
    }
    for (const name of ["claims", "results", "reviews"]) {
      await privateDirectory(join(directory, name));
    }
    const manifestPath = join(directory, "manifest.json");
    if (!await exists(manifestPath)) {
      for (const name of ["claims", "results", "reviews"]) {
        await onlyEntries(join(directory, name), []);
      }
      check(!await exists(join(directory, "stop.json")));
      await claimJson(manifestPath, {
        version: continuation ? "photo_model_run_v2" : "photo_model_run_v1",
        createdAt: new Date().toISOString(),
        binding: initial.binding,
      });
    }
    const manifest = fields(await readJson(manifestPath), [
      "version",
      "createdAt",
      "binding",
    ]);
    check(
      manifest.version ===
        (continuation ? "photo_model_run_v2" : "photo_model_run_v1"),
    );
    timestamp(manifest.createdAt);
    if (
      await fingerprintJson(manifest.binding) !==
        await fingerprintJson(initial.binding)
    ) {
      return await configurationStop(directory);
    }
    const runDigest = await fingerprintJson(manifest), packet = initial.packet;
    const names = packet.report.order.filter((a) =>
      !continuation || a.ordinal !== 1
    ).map((a) => filename(a.ordinal));
    for (const name of ["claims", "results", "reviews"]) {
      await onlyEntries(join(directory, name), names);
    }
    const entries = new Map<number, Entry>();
    let stop: StopReason | null = null, claimed = 0, heldNanoUsd = 0;
    const stopPath = join(directory, "stop.json");
    if (await exists(stopPath)) {
      const v = fields(await readJson(stopPath), [
        "version",
        "runDigest",
        "reason",
      ]);
      check(v.version === "photo_model_stop_v1" && v.runDigest === runDigest);
      member(v.reason, STOP_REASONS);
      stop = v.reason;
    }
    const reconcile = async () => {
      entries.clear();
      claimed = initial.parent ? 1 : 0;
      heldNanoUsd = initial.parent?.reservedNanoUsd ?? 0;
      if (initial.parent) entries.set(1, initial.parent.entry);
      let gap = false;
      for (const a of packet.report.order) {
        if (continuation && a.ordinal === 1) continue;
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
          c.version === "photo_model_claim_v1" && c.runDigest === runDigest &&
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
        const record = parsePhotoModelRecord(
          await readJson(resultPath),
          a,
          runDigest,
          assignmentDigest,
        );
        const expectedCost =
          record.returnedModel === a.model && record.serviceTier === "default"
            ? photoModelCostUpper(record.usage, a, packet.pricing)
            : null;
        check(
          record.estimatedUpperNanoUsd === expectedCost &&
            (expectedCost === null || expectedCost <= reserve(a)),
        );
        if (record.reason !== "completed") {
          stop ??= "provider_failure";
          gap = true;
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
          r.version === "photo_model_review_v1" && r.runDigest === runDigest &&
            r.ordinal === a.ordinal &&
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
          Object.values(entry.ratings).some((rating) =>
            rating.reason === "review_unavailable"
          )
        ) {
          stop ??= "review_missing";
          gap = true;
        }
        if (
          a.phase === "screen" && !screenPass(packet, a, entry, continuation)
        ) {
          stop ??= "screen_failed";
          gap = true;
        }
        if (a.phase === "challenge") {
          check(
            packet.report.order.filter((p) => p.phase === "screen").every((p) =>
              entries.has(p.ordinal) &&
              screenPass(packet, p, entries.get(p.ordinal)!, continuation)
            ),
          );
        }
      }
    };
    const saveState = async () => {
      if (stop && !await exists(stopPath)) {
        await claimJson(stopPath, {
          version: "photo_model_stop_v1",
          runDigest,
          reason: stop,
        });
      }
      const state = {
        version: continuation ? "photo_model_state_v2" : "photo_model_state_v1",
        ...(continuation
          ? {
            inheritedCalls: initial.parent ? 1 : 0,
            newlyClaimedCalls: claimed - (initial.parent ? 1 : 0),
            screeningPolicy: PHOTO_MODEL_REFERENCE_GAP_POLICY,
            referenceGapOrdinals: [...entries].filter(([, e]) =>
              Object.values(e.ratings).some((r) =>
                r.status === "not_assessable" &&
                r.reason === "insufficient_reference"
              )
            ).map(([ordinal]) => ordinal),
            explanationEvidenceComplete: entries.size === 18 &&
              [...entries.values()].every((e) => ratingsPass(e.ratings)),
          }
          : {}),
        runDigest,
        stop,
        claimedCalls: claimed,
        completedCalls: [...entries.values()].filter((e) =>
          e.record.reason === "completed"
        ).length,
        heldReservationUsd: heldNanoUsd / 1e9,
        complete: claimed === 18 && entries.size === 18 && stop === null,
        evidenceStatus: packet.report.evidenceStatus,
        // Quality selection remains a separate report; completing requests never activates routing.
        productionActivationAuthorized: false,
      };
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
      if (a.phase === "challenge") {
        check(
          packet.report.order.filter((p) => p.phase === "screen").every((p) =>
            entries.has(p.ordinal) &&
            screenPass(packet, p, entries.get(p.ordinal)!, continuation)
          ),
        );
      }
      const prepareCall = async () => {
        const current = await load();
        check(
          await fingerprintJson(current.binding) ===
            await fingerprintJson(initial.binding),
        );
        const input = current.packet.corpus.cases.find((c) =>
          c.input.caseId === a.caseId
        )!.input;
        const request = await prepareEvidence(root, input),
          snapshot = openAIPhotoModelSnapshot(request, a.profile);
        check(
          await fingerprintJson(snapshot) === a.snapshotDigest &&
            await fingerprintJson(
                buildOpenAIPhotoModelRequestParameters(request, snapshot),
              ) === a.requestDigest,
        );
        const execution = live
          ? createAIExecution(
            createOpenAIPhotoModelEvaluationAdapter(current.credential),
            request,
            snapshot,
          )
          : null;
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
        version: "photo_model_claim_v1",
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
      const { record, display } = projectPhotoModelOutcome(
        outcome,
        input,
        request,
        card,
        a,
        runDigest,
        assignmentDigest,
        current.packet.taxonomy,
        current.packet.pricing,
      );
      // Persist completion before opening the transient view. Losing that view never triggers another call.
      await claimJson(join(directory, "results", name), record);
      if (record.reason === "completed") {
        const ratings = live
          ? await reviewExplanation(display, 600000, true)
          : await dependencies!.review(display);
        await claimJson(join(directory, "reviews", name), {
          version: "photo_model_review_v1",
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
        if (!ratings) stop = "review_missing";
      }
      await reconcile();
      await saveState();
      if (stop) break;
    }
    return await saveState();
  });
}
