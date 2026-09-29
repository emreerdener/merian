/** Explicit local evaluation approval; never production routing authority. */
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import type { PhotoModelPacket } from "./photoModelPreparation.ts";
import { hash, timestamp } from "./runContracts.ts";
import { fields, requireCondition as check, token } from "./validation.ts";

export const PHOTO_MODEL_REFERENCE_GAP_POLICY = "reference_gaps_recorded_v1";
export interface PhotoModelParentBinding {
  parentRunDigest: string;
  parentArtifactsDigest: string;
}
export interface PhotoModelApproval {
  version:
    | "photo_model_approval_v1"
    | "photo_model_continuation_approval_v1"
    | "photo_model_candidate_approval_v1";
  project: "naturebook";
  operation:
    | "18_call_luna_sol_photo_comparison"
    | "remaining_17_luna_sol_photo_comparison"
    | "18_call_luna_evidence_limits_sol_photo_comparison";
  parentRunDigest?: string;
  parentArtifactsDigest?: string;
  screeningPolicy?: typeof PHOTO_MODEL_REFERENCE_GAP_POLICY;
  maxAdditionalCalls?: 17;
  planDigest: string;
  sourceCommit: string;
  sourceDigest: string;
  credentialSha256: string;
  budgetUsd: number;
  approvedAt: string;
  expiresAt: string;
  recordRef: string;
  reviewerRef: string;
  delegationRef: string;
}
export async function validatePhotoModelApproval(
  value: unknown,
  packet: PhotoModelPacket,
  credential: string,
  now: number,
  parent?: PhotoModelParentBinding,
): Promise<PhotoModelApproval> {
  const candidate = packet.plan.version === "photo_model_plan_v3";
  check(!candidate || parent === undefined);
  const v = fields(value, [
    "version",
    "project",
    "operation",
    "planDigest",
    "sourceCommit",
    "sourceDigest",
    "credentialSha256",
    "budgetUsd",
    "approvedAt",
    "expiresAt",
    "recordRef",
    "reviewerRef",
    "delegationRef",
    ...(parent
      ? [
        "parentRunDigest",
        "parentArtifactsDigest",
        "maxAdditionalCalls",
      ]
      : []),
    ...(parent || candidate ? ["screeningPolicy"] : []),
  ]);
  check(
    v.version ===
        (parent
          ? "photo_model_continuation_approval_v1"
          : candidate
          ? "photo_model_candidate_approval_v1"
          : "photo_model_approval_v1") &&
      v.project === "naturebook" &&
      v.operation ===
        (parent
          ? "remaining_17_luna_sol_photo_comparison"
          : candidate
          ? "18_call_luna_evidence_limits_sol_photo_comparison"
          : "18_call_luna_sol_photo_comparison"),
  );
  if (candidate) check(v.screeningPolicy === PHOTO_MODEL_REFERENCE_GAP_POLICY);
  if (parent) {
    hash(v.parentRunDigest);
    hash(v.parentArtifactsDigest);
    check(
      v.parentRunDigest === parent.parentRunDigest &&
        v.parentArtifactsDigest === parent.parentArtifactsDigest &&
        v.screeningPolicy === PHOTO_MODEL_REFERENCE_GAP_POLICY &&
        v.maxAdditionalCalls === 17,
    );
  }
  check(
    (packet.plan.version === "photo_model_plan_v2" || candidate) &&
      packet.corpus.evidenceOrigin === "real" &&
      packet.plan.inputApproval !== null && !packet.report.source.dirty,
  );
  check(
    v.planDigest === await fingerprintJson(packet.plan) &&
      v.sourceCommit === packet.report.source.commit &&
      v.sourceDigest === packet.report.source.digest,
  );
  hash(v.planDigest);
  hash(v.sourceDigest);
  hash(v.credentialSha256);
  check(
    typeof v.sourceCommit === "string" && /^[0-9a-f]{40}$/.test(v.sourceCommit),
  );
  check(
    credential.length > 0 && credential.length <= 512 && !/\s/.test(credential),
  );
  check(
    v.credentialSha256 ===
      await fingerprintBytes(new TextEncoder().encode(credential)),
  );
  check(
    v.budgetUsd === packet.plan.budgetUsd &&
      packet.report.order.reduce(
          (n, a) => n + Math.ceil(a.reservedNanoUsd * 11 / 10),
          0,
        ) <=
        Math.floor(packet.plan.budgetUsd * 1e9),
  );
  timestamp(v.approvedAt);
  timestamp(v.expiresAt);
  check(
    Date.parse(v.approvedAt) <= now && now < Date.parse(v.expiresAt) &&
      Date.parse(v.expiresAt) - Date.parse(v.approvedAt) <= 86400000,
  );
  token(v.recordRef);
  token(v.reviewerRef);
  token(v.delegationRef);
  return structuredClone(v) as unknown as PhotoModelApproval;
}
