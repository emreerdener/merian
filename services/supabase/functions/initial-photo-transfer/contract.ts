/** Dormant wire contract. A request identifies saved work; it grants no IO. */
import {
  type AllocationRequest,
  parseAllocationRequest,
} from "../initial-photo-allocation/contract.ts";
import { matchesInitialSchema } from "../_shared/initialAnalysis/schema.ts";
import { initialMediaUnavailable } from "../_shared/initialAnalysis/mediaBinding.ts";
import {
  type CpmPhotoStatusIdentity,
  snapshotCpmPhotoStatusIdentity,
} from "../_shared/initialAnalysis/cpmPhotoWriteStatus.ts";
import schema from "./schema-v1.json" with { type: "json" };

import roleProgress from "./role-progress-schema-v2.json" with { type: "json" };

export const TRANSFER_BODY_LIMIT = 2 * 1048576 + 4096;
export const TRANSFER_REPLY_LIMIT = 8192;
export type TransferRequest = Readonly<{
  action: "issue" | "status" | "role_progress";
  scan: string;
  assignmentDigest: string;
  object: string;
  created: number;
  expires: number;
  attempt: string | null;
  allocation: AllocationRequest | null;
}>;

export function parseTransferRequest(body: unknown): TransferRequest {
  if (
    !matchesInitialSchema(body, schema.issue) &&
    !matchesInitialSchema(body, schema.status) &&
    !matchesInitialSchema(body, roleProgress)
  ) {
    throw initialMediaUnavailable();
  }
  // The executable closed schema checks every key and primitive before mapping.
  const value = body as {
    action: "issue" | "status" | "role_progress";
    scan_id: string;
    assignment_digest: string;
    object_id: string;
    allocation_created_at_ms: number;
    allocation_expires_at_ms: number;
    attempt_id?: string;
    candidate_canonical?: string;
  };
  if (
    value.allocation_expires_at_ms !==
      value.allocation_created_at_ms + 1_800_000
  ) throw initialMediaUnavailable();
  const allocation = value.action === "issue"
    ? parseAllocationRequest({
      version: 3,
      action: "status",
      candidate_canonical: value.candidate_canonical,
      saved_assignment_digest: value.assignment_digest,
    })
    : null;
  if (allocation !== null && allocation.scanID !== value.scan_id) {
    throw initialMediaUnavailable();
  }
  return Object.freeze({
    action: value.action,
    scan: value.scan_id,
    assignmentDigest: value.assignment_digest,
    object: value.object_id,
    created: value.allocation_created_at_ms,
    expires: value.allocation_expires_at_ms,
    attempt: value.attempt_id ?? null,
    allocation,
  });
}

export function statusIdentity(
  owner: string,
  request: TransferRequest,
): CpmPhotoStatusIdentity {
  return snapshotCpmPhotoStatusIdentity({
    owner,
    scan: request.scan,
    assignment_digest: request.assignmentDigest,
    object: request.object,
    allocation_created_at_ms: request.created,
    allocation_expires_at_ms: request.expires,
  });
}
