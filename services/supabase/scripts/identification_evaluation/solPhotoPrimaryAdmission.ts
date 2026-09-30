/** Fresh owner approval, scoped to one source, credential, packet and 18-call schedule. */
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import type { SolPrimaryPacket } from "./solPhotoPrimaryLivePreparation.ts";
import { SOL_PRIMARY_SCREEN_POLICY } from "./solPhotoPrimaryContracts.ts";
import { hash, timestamp } from "./runContracts.ts";
import { fields, requireCondition as check, token } from "./validation.ts";

export interface SolPrimaryApproval {
  version: "sol_photo_primary_approval_v1";
  project: "naturebook";
  operation: "18_call_sol_primary_photo_comparison";
  screeningPolicy: typeof SOL_PRIMARY_SCREEN_POLICY;
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
export async function validateSolPrimaryApproval(
  value: unknown,
  packet: SolPrimaryPacket,
  credential: string,
  now: number,
): Promise<SolPrimaryApproval> {
  const v = fields(value, [
    "version",
    "project",
    "operation",
    "screeningPolicy",
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
  ]);
  check(
    v.version === "sol_photo_primary_approval_v1" &&
      v.project === "naturebook" &&
      v.operation === "18_call_sol_primary_photo_comparison" &&
      v.screeningPolicy === SOL_PRIMARY_SCREEN_POLICY,
  );
  check(
    packet.corpus.evidenceOrigin === "real" &&
      packet.plan.inputApproval !== null &&
      packet.report.source.dirty === false,
  );
  for (const k of ["planDigest", "sourceDigest", "credentialSha256"]) {
    hash(v[k]);
  }
  check(
    typeof v.sourceCommit === "string" && /^[0-9a-f]{40}$/.test(v.sourceCommit),
  );
  check(
    v.planDigest === await fingerprintJson(packet.plan) &&
      v.sourceCommit === packet.report.source.commit &&
      v.sourceDigest === packet.report.source.digest,
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
      packet.report.budgetFitsRegionalReservation,
  );
  timestamp(v.approvedAt);
  timestamp(v.expiresAt);
  check(
    Date.parse(v.approvedAt) <= now && now < Date.parse(v.expiresAt) &&
      Date.parse(v.expiresAt) - Date.parse(v.approvedAt) <= 86400000,
  );
  for (const k of ["recordRef", "reviewerRef", "delegationRef"]) token(v[k]);
  return structuredClone(v) as unknown as SolPrimaryApproval;
}
