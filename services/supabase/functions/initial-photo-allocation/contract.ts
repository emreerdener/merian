/** App projection only. Private assignments never cross this boundary. */
import {
  invalidInitialInput,
  parseInitialCanonicalText,
} from "../_shared/initialAnalysis/canonical.ts";
import {
  initialCpmPhotoCandidateDigest,
  parseInitialCpmPhotoCandidate,
} from "../_shared/initialAnalysis/cpmPhotoCandidate.ts";
import { initialCpmPhotoContentDigest } from "../_shared/initialAnalysis/cpmPhotoContent.ts";
import { validateInitialCpmPhotoRecovery } from "../_shared/initialAnalysis/cpmPhotoRecovery.ts";
import { matchesInitialSchema } from "../_shared/initialAnalysis/schema.ts";
import schema from "./schema-v1.json" with { type: "json" };

export const ALLOCATION_BODY_LIMIT = 2 * 1048576 + 4096;
export type AllocationRequest = Readonly<{
  action: "create" | "status";
  candidateCanonical: string;
  scanID: string;
  packageID: string;
  savedAssignmentDigest: string | null;
}>;

export function parseAllocationRequest(body: unknown): AllocationRequest {
  if (
    !matchesInitialSchema(body, schema.create) &&
    !matchesInitialSchema(body, schema.status)
  ) return invalidInitialInput();
  const request = body as {
    action: "create" | "status";
    candidate_canonical: string;
    saved_assignment_digest?: string | null;
  };
  const candidateCanonical = parseInitialCpmPhotoCandidate(
    request.candidate_canonical,
  );
  const candidate = JSON.parse(candidateCanonical) as {
    content_canonical: string;
  };
  const content = JSON.parse(candidate.content_canonical) as {
    scan_id: string;
    package_id: string;
  };
  return Object.freeze({
    action: request.action,
    candidateCanonical,
    scanID: content.scan_id,
    packageID: content.package_id,
    savedAssignmentDigest: request.saved_assignment_digest ?? null,
  });
}

/** Terminal association describes the request, not proof of candidate equality,
 * remote cancellation, deletion, or permission to release local source bytes. */
export async function projectAllocationReceipt(
  request: AllocationRequest,
  privateResponse: unknown,
): Promise<unknown> {
  const candidate = JSON.parse(request.candidateCanonical);
  const recovery = JSON.parse(
    await validateInitialCpmPhotoRecovery(candidate, privateResponse, null),
  );
  const content = JSON.parse(candidate.content_canonical);
  const base = {
    version: 1,
    variant: "client_prepared_photo",
    authority: "none",
    scan_id: request.scanID,
    package_id: request.packageID,
    candidate_digest: await initialCpmPhotoCandidateDigest(candidate),
    content_digest: await initialCpmPhotoContentDigest(content),
  };
  if (recovery.outcome === "terminal_held") {
    const receipt = {
      ...base,
      outcome: "terminal_held",
      reason: recovery.reason,
    };
    if (!matchesInitialSchema(receipt, schema.terminal_held)) {
      return invalidInitialInput();
    }
    return receipt;
  }
  if (
    request.savedAssignmentDigest !== null &&
    request.savedAssignmentDigest !== recovery.assignment_digest
  ) return invalidInitialInput();
  // The recovery validator already checked all roles, identities, protocol,
  // processor, digests and original 30-minute clock against this exact candidate.
  const assignment = parseInitialCanonicalText(
    recovery.assignment_canonical,
  ) as { created_at_ms: number; expires_at_ms: number };
  const receipt = {
    ...base,
    outcome: "allocated",
    assignment_digest: recovery.assignment_digest,
    created_at_ms: assignment.created_at_ms,
    expires_at_ms: assignment.expires_at_ms,
  };
  if (!matchesInitialSchema(receipt, schema.allocated)) {
    return invalidInitialInput();
  }
  return receipt;
}
