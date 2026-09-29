/** One fixed continuation: inherit the stopped first attempt, never re-dispatch it. */
import { join } from "node:path";
import { assertOfflinePermissions } from "./admission.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  parseRatings,
  type Ratings,
  ratingsPass,
  RUBRIC,
} from "./explanationContracts.ts";
import {
  atomicJson,
  exists,
  privateDirectory,
  readJson,
  withRunLock,
} from "./files.ts";
import {
  PHOTO_MODEL_REFERENCE_GAP_POLICY,
  validatePhotoModelApproval,
} from "./photoModelAdmission.ts";
import {
  loadPhotoModelPacket,
  type PhotoModelAssignment,
  type PhotoModelPacket,
} from "./photoModelPreparation.ts";
import {
  parsePhotoModelRecord,
  photoModelCostUpper,
  type PhotoModelRecord,
} from "./photoModelRecords.ts";
import { hash, type SourceIdentity, timestamp } from "./runContracts.ts";
import { assessReference } from "./scoring.ts";
import { fields, requireCondition as check } from "./validation.ts";

export interface PhotoModelEntry {
  record: PhotoModelRecord;
  ratings: Ratings;
}
export function photoModelScreenPass(
  packet: PhotoModelPacket,
  a: PhotoModelAssignment,
  entry: PhotoModelEntry,
  referenceGaps = false,
): boolean {
  if (entry.record.reason !== "completed") return false;
  const reviewEligible = referenceGaps
    ? Object.values(entry.ratings).every((r) =>
      r.status === "pass" ||
      (r.status === "not_assessable" && r.reason === "insufficient_reference")
    )
    : ratingsPass(entry.ratings);
  if (!reviewEligible) return false;
  const reference = packet.corpus.cases.find((c) =>
    c.input.caseId === a.caseId
  )!.provisionalReference!;
  const assessment = assessReference(reference, entry.record.prediction);
  return assessment.subjectCorrect &&
    (assessment.correct || assessment.appropriateUnresolved);
}
async function exactEntries(path: string, names: string[]) {
  const found: string[] = [];
  for await (const e of Deno.readDir(path)) {
    check(!e.isSymlink && names.includes(e.name));
    found.push(e.name);
  }
  check(found.length === names.length);
}

/** Caller holds the original run lock. Mutable state.json is never authority. */
export async function loadPhotoModelParent(
  root: string,
  packet: PhotoModelPacket,
  mode: "offline" | "live",
  credential?: string,
) {
  const dir = join(root, "photo-model-run");
  await exactEntries(dir, [
    ".lock",
    "manifest.json",
    "claims",
    "results",
    "reviews",
    "state.json",
    "stop.json",
  ]);
  for (const name of ["claims", "results", "reviews"]) {
    const stat = await Deno.lstat(join(dir, name));
    check(stat.isDirectory && !stat.isSymlink);
    await exactEntries(join(dir, name), ["01.json"]);
  }
  const manifest = fields(await readJson(join(dir, "manifest.json")), [
    "version",
    "createdAt",
    "binding",
  ]);
  check(manifest.version === "photo_model_run_v1");
  timestamp(manifest.createdAt);
  const binding = fields(manifest.binding, [
    "version",
    "mode",
    "source",
    "planDigest",
    "order",
    "budgetUsd",
    "reservedNanoUsd",
    "billingMultiplier",
    "approvalDigest",
    "rubricDigest",
    "reviewerRef",
    "delegationRef",
  ]);
  const oldSource = fields(binding.source, [
    "commit",
    "dirty",
    "digest",
    "sdk",
  ]);
  check(
    typeof oldSource.commit === "string" &&
      /^[0-9a-f]{40}$/.test(oldSource.commit),
  );
  hash(oldSource.digest);
  check(
    typeof oldSource.dirty === "boolean" &&
      oldSource.sdk === packet.report.source.sdk,
  );
  check(
    binding.version === "photo_model_run_binding_v1" && binding.mode === mode &&
      binding.planDigest === packet.report.planDigest &&
      binding.budgetUsd === packet.plan.budgetUsd &&
      binding.billingMultiplier === 1.1 &&
      binding.reservedNanoUsd ===
        packet.report.order.reduce(
          (n, a) => n + Math.ceil(a.reservedNanoUsd * 11 / 10),
          0,
        ) &&
      await fingerprintJson(binding.order) ===
        await fingerprintJson(packet.report.order) &&
      binding.rubricDigest === await fingerprintJson(RUBRIC),
  );
  const parentRunDigest = await fingerprintJson(manifest);
  const stop = fields(await readJson(join(dir, "stop.json")), [
    "version",
    "runDigest",
    "reason",
  ]);
  check(
    stop.version === "photo_model_stop_v1" &&
      stop.runDigest === parentRunDigest && stop.reason === "screen_failed",
  );
  const a = packet.report.order[0], assignmentDigest = await fingerprintJson(a);
  check(a.ordinal === 1 && a.phase === "screen");
  const claim = fields(await readJson(join(dir, "claims", "01.json")), [
    "version",
    "runDigest",
    "ordinal",
    "assignmentDigest",
    "reservedNanoUsd",
    "startedAt",
  ]);
  timestamp(claim.startedAt);
  check(
    claim.version === "photo_model_claim_v1" &&
      claim.runDigest === parentRunDigest &&
      claim.ordinal === 1 && claim.assignmentDigest === assignmentDigest &&
      claim.reservedNanoUsd === Math.ceil(a.reservedNanoUsd * 11 / 10),
  );
  const record = parsePhotoModelRecord(
    await readJson(join(dir, "results", "01.json")),
    a,
    parentRunDigest,
    assignmentDigest,
  );
  check(
    record.reason === "completed" &&
      record.estimatedUpperNanoUsd ===
        photoModelCostUpper(record.usage, a, packet.pricing) &&
      record.estimatedUpperNanoUsd !== null &&
      record.estimatedUpperNanoUsd <= claim.reservedNanoUsd,
  );
  const review = fields(await readJson(join(dir, "reviews", "01.json")), [
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
    review.version === "photo_model_review_v1" &&
      review.runDigest === parentRunDigest &&
      review.ordinal === 1 &&
      review.resultDigest === await fingerprintJson(record) &&
      review.factsDigest === a.factsDigest &&
      review.rubricDigest === binding.rubricDigest &&
      review.method === "assistant_local_v1" &&
      review.reviewerRef === binding.reviewerRef &&
      review.delegationRef === binding.delegationRef,
  );
  const entry = { record, ratings: parseRatings(review.ratings) };
  check(
    !ratingsPass(entry.ratings) && photoModelScreenPass(packet, a, entry, true),
  );
  let approval: unknown = null;
  if (mode === "live") {
    check(oldSource.dirty === false);
    approval = await readJson(join(root, "photo-model-approval.json"));
    check(binding.approvalDigest === await fingerprintJson(approval));
    if (credential !== undefined) {
      // Historical authorization is checked at the claim time, not renewed as live authority.
      await validatePhotoModelApproval(
        approval,
        {
          ...packet,
          report: {
            ...packet.report,
            source: oldSource as unknown as SourceIdentity,
          },
        },
        credential,
        Date.parse(claim.startedAt),
      );
    }
  } else check(binding.approvalDigest === null);
  return {
    parentRunDigest,
    parentArtifactsDigest: await fingerprintJson({
      manifest,
      stop,
      claim,
      record,
      review,
      approval,
    }),
    entry,
    reservedNanoUsd: claim.reservedNanoUsd as number,
    startedAt: claim.startedAt,
  };
}

export async function preparePhotoModelContinuation(
  root: string,
  source: SourceIdentity,
) {
  await assertOfflinePermissions();
  const packet = await loadPhotoModelPacket(root, source);
  // No writes to the old journal, including its preflight or mutable summary.
  check(await exists(join(root, "photo-model-run")));
  await privateDirectory(join(root, "photo-model-run"));
  return await withRunLock(join(root, "photo-model-run"), async () => {
    const parent = await loadPhotoModelParent(
      root,
      packet,
      packet.corpus.evidenceOrigin === "real" ? "live" : "offline",
    );
    const report = {
      ...packet.report,
      version: "photo_model_continuation_preflight_v1",
      parentRunDigest: parent.parentRunDigest,
      parentArtifactsDigest: parent.parentArtifactsDigest,
      inheritedCalls: 1,
      maxAdditionalCalls: 17,
      screeningPolicy: PHOTO_MODEL_REFERENCE_GAP_POLICY,
    };
    await atomicJson(
      join(root, "photo-model-continuation-preflight.json"),
      report,
    );
    return report;
  });
}
