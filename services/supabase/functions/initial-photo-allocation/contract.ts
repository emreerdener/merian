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
import schemaV2 from "./schema-v2.json" with { type: "json" };
import schemaV3 from "./schema-v3.json" with { type: "json" };
import { validateInitialCpmPhotoBoundRecovery } from "../_shared/initialAnalysis/cpmPhotoBoundRecovery.ts";

// Six mapping entries, the receipt and the opaque backend tuple fit in 2048.
// No URLs, configuration contents or bearer may enter the reply.
export const ALLOCATION_REPLY_LIMIT = 2048;
export const ALLOCATION_BODY_LIMIT = 2 * 1048576 + 4096;
export type AllocationRequest = Readonly<{
  version: 1 | 2 | 3;
  action: "create" | "status";
  candidateCanonical: string;
  scanID: string;
  packageID: string;
  savedAssignmentDigest: string | null;
}>;

export function parseAllocationRequest(body: unknown): AllocationRequest {
  if (
    !matchesInitialSchema(body, schema.create) &&
    !matchesInitialSchema(body, schema.status) &&
    !matchesInitialSchema(body, schemaV2.create) &&
    !matchesInitialSchema(body, schemaV2.status) &&
    !matchesInitialSchema(body, schemaV3.create) &&
    !matchesInitialSchema(body, schemaV3.status)
  ) return invalidInitialInput();
  const request = body as {
    version: 1 | 2 | 3;
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
    version: request.version,
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
    await (request.version === 3
      ? validateInitialCpmPhotoBoundRecovery
      : validateInitialCpmPhotoRecovery)(candidate, privateResponse, null),
  );
  const content = JSON.parse(candidate.content_canonical);
  const replySchema = request.version === 1
    ? schema
    : request.version === 2
    ? schemaV2
    : schemaV3;
  const base = {
    version: request.version,
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
    if (!matchesInitialSchema(receipt, replySchema.terminal_held)) {
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
  ) as {
    created_at_ms: number;
    expires_at_ms: number;
    preparation: {
      role_mapping: {
        photo_ordinal: number;
        role: string;
        object_id: string;
        declaration: { reference_id: string };
      }[];
    };
  };
  const receipt = {
    ...base,
    outcome: "allocated",
    ...(request.version === 3
      ? {
        backend_generation: recovery.backend_generation,
        backend_configuration_digest: recovery.backend_configuration_digest,
      }
      : {}),
    assignment_digest: recovery.assignment_digest,
    created_at_ms: assignment.created_at_ms,
    expires_at_ms: assignment.expires_at_ms,
    ...(request.version >= 2
      ? {
        role_mapping: assignment.preparation.role_mapping.map((entry) => ({
          photo_ordinal: entry.photo_ordinal,
          role: entry.role,
          reference_id: entry.declaration.reference_id,
          object_id: entry.object_id,
        })),
      }
      : {}),
  };
  if (
    !matchesInitialSchema(receipt, replySchema.allocated) ||
    new TextEncoder().encode(JSON.stringify(receipt)).length >
      ALLOCATION_REPLY_LIMIT
  ) {
    return invalidInitialInput();
  }
  return receipt;
}
