import {
  type AllocationRequest,
  parseAllocationRequest,
  projectAllocationReceipt,
} from "../initial-photo-allocation/contract.ts";
import type { CpmAdmissionIdentity } from "../_shared/initialAnalysis/cpmPhotoAdmission.ts";
import { initialCanonicalText } from "../_shared/initialAnalysis/canonical.ts";
import {
  initialMediaUnavailable,
  mediaRecord,
} from "../_shared/initialAnalysis/mediaBinding.ts";
import { matchesInitialSchema } from "../_shared/initialAnalysis/schema.ts";
import {
  checkInitialDeadline,
  initialAbortable,
} from "../_shared/initialAnalysis/transport.ts";
import schema from "./cohort-verification-schema-v3.json" with { type: "json" };
import allocated from "../initial-photo-allocation/schema-v3.json" with {
  type: "json",
};

export type CohortAdmissionRuntime = Readonly<{
  admit(identity: CpmAdmissionIdentity, signal: AbortSignal): Promise<unknown>;
}>;
export function parseCohortVerification(body: unknown) {
  if (!matchesInitialSchema(body, schema)) throw initialMediaUnavailable();
  const r = body as {
    scan_id: string;
    assignment_digest: string;
    candidate_canonical: string;
    allocation_created_at_ms: number;
    allocation_expires_at_ms: number;
    backend_generation: string;
    backend_configuration_digest: string;
  };
  const allocation = parseAllocationRequest({
    version: 3,
    action: "status",
    candidate_canonical: r.candidate_canonical,
    saved_assignment_digest: r.assignment_digest,
  });
  if (
    allocation.scanID !== r.scan_id ||
    r.allocation_expires_at_ms !== r.allocation_created_at_ms + 1_800_000
  ) throw initialMediaUnavailable();
  return Object.freeze({
    action: "verify_cohort" as const,
    allocation,
    created: r.allocation_created_at_ms,
    expires: r.allocation_expires_at_ms,
    generation: r.backend_generation,
    configuration: r.backend_configuration_digest,
  });
}

/** Reconstruct the private admission identity from the original server
 * assignment. The caller supplies no verification report, owner or funding.
 * The runtime owns the original begin/recover fence and reads all members. */
export async function verifyCohort(
  request: ReturnType<typeof parseCohortVerification>,
  owner: string,
  deps: {
    recover(
      owner: string,
      request: AllocationRequest,
      signal: AbortSignal,
    ): Promise<unknown>;
    admission?: CohortAdmissionRuntime;
  },
  signal: AbortSignal,
) {
  if (!deps.admission) throw initialMediaUnavailable();
  const source = JSON.parse(
    initialCanonicalText(
      await initialAbortable(
        signal,
        () => deps.recover(owner, request.allocation, signal),
      ),
    ),
  );
  const projection = await initialAbortable(
    signal,
    () => projectAllocationReceipt(request.allocation, source),
  );
  if (!matchesInitialSchema(projection, allocated.allocated)) {
    throw initialMediaUnavailable();
  }
  const receipt = projection as {
    created_at_ms: number;
    expires_at_ms: number;
    backend_generation: string;
    backend_configuration_digest: string;
    candidate_digest: string;
  };
  if (
    receipt.created_at_ms !== request.created ||
    receipt.expires_at_ms !== request.expires ||
    receipt.backend_generation !== request.generation ||
    receipt.backend_configuration_digest !== request.configuration
  ) throw initialMediaUnavailable();
  const identity = Object.freeze({
    owner_id: owner,
    scan_id: request.allocation.scanID,
    candidate_canonical: request.allocation.candidateCanonical,
    assignment_canonical: source.assignment_canonical as string,
    assignment_digest: request.allocation.savedAssignmentDigest!,
  });
  const ack = mediaRecord(
    await initialAbortable(
      signal,
      () => deps.admission!.admit(identity, signal),
    ),
    ["version", "outcome", "authority"],
  );
  if (
    ack.version !== 1 ||
    (ack.outcome !== "admitted" && ack.outcome !== "held") ||
    ack.authority !== "none"
  ) throw initialMediaUnavailable();
  checkInitialDeadline(signal);
  return Object.freeze({
    version: 3,
    outcome: ack.outcome,
    authority: "none",
    scan_id: identity.scan_id,
    assignment_digest: identity.assignment_digest,
    candidate_digest: receipt.candidate_digest,
    backend_generation: request.generation,
    backend_configuration_digest: request.configuration,
  });
}
