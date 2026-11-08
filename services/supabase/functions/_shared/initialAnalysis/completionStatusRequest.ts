/** Prepared request boundary for the existing status owner; no live route import.
 * Authentication precedes this decoder. A client owner field is never authority.
 * Failure must not fall through to legacy missing-scan repair or retry. */
import {
  type InitialCompletionAdmission,
  initialCompletionAdmissionKeys,
  snapshotInitialCompletionAdmission,
} from "./completionAcquisition.ts";
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { decodeCpmCompletionAdmission } from "./cpmCompletionAdmission.ts";
import {
  initialCpmPhotoCandidateDigest,
  parseInitialCpmPhotoCandidate,
} from "./cpmPhotoCandidate.ts";
import { initialCpmPhotoContentDigest } from "./cpmPhotoContent.ts";

/** Native saved facts: full assignment remains server-owned. */
export interface InitialStatusCpmBinding {
  readonly owner_id: string;
  readonly scan_id: string;
  readonly candidate_canonical: string;
  readonly candidate_digest: string;
  readonly content_digest: string;
  readonly assignment_digest: string;
  readonly backend_generation: string;
  readonly backend_configuration_digest: string;
}
import { mediaDigest, mediaUUID } from "./mediaBinding.ts";

export const initialStatusAdmissionRequestBytes = 2 * 1048576 + 4096;
export const initialStatusCompletionRequestBytes = 8192;
export type InitialStatusRecoveryRequest =
  | Readonly<{
    phase: "admission";
    scan_id: string;
    original: Readonly<InitialStatusCpmBinding>;
  }>
  | Readonly<{
    phase: "completion";
    scan_id: string;
    original: Readonly<InitialCompletionAdmission>;
  }>;
const bindingKeys = [
  "owner_id",
  "scan_id",
  "candidate_canonical",
  "candidate_digest",
  "content_digest",
  "assignment_digest",
  "backend_generation",
  "backend_configuration_digest",
] as const;
const invalid = () => new Error("initial_status_recovery_request_invalid");
function closed(value: unknown, keys: readonly string[]) {
  if (
    !value || typeof value !== "object" ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) throw invalid();
  const fields = Object.getOwnPropertyDescriptors(value);
  if (
    Reflect.ownKeys(value).length !== keys.length ||
    Object.keys(fields).length !== keys.length ||
    keys.some((key) =>
      !Object.hasOwn(fields, key) || !fields[key].enumerable ||
      !("value" in fields[key])
    )
  ) throw invalid();
  return Object.fromEntries(
    keys.map((key) => [key, fields[key].value as unknown]),
  );
}

/** Snapshot before the admission digest await. Only fixed original reads may
 * consume the result; it grants no admission, execution, settlement or repair.
 * Raw HTTP collection must enforce the matching byte cap before JSON parsing. */
export async function decodeInitialStatusRecoveryRequest(
  value: unknown,
  authenticatedOwnerID: string,
): Promise<InitialStatusRecoveryRequest> {
  const owner = mediaUUID(authenticatedOwnerID);
  const body = closed(value, ["scan_id", "initial_recovery"]);
  const scan = mediaUUID(body.scan_id);
  const recovery = closed(body.initial_recovery, [
    "version",
    "phase",
    "original",
  ]);
  if (
    recovery.version !== 1 ||
    (recovery.phase !== "admission" && recovery.phase !== "completion")
  ) throw invalid();
  const phase = recovery.phase;
  const original = closed(
    recovery.original,
    phase === "admission" ? bindingKeys : initialCompletionAdmissionKeys,
  );
  if (original.owner_id !== owner || original.scan_id !== scan) throw invalid();
  if (phase === "admission") {
    const candidate = original.candidate_canonical;
    if (
      typeof candidate !== "string" || candidate.length > 1048576 ||
      new TextEncoder().encode(candidate).length > 1048576
    ) throw invalid();
    // Validate/copy all facts before hashing can yield. Full assignment, funding
    // and original backend association must still be resolved by the fixed SQL reader.
    const saved = Object.freeze({
      owner_id: owner,
      scan_id: scan,
      candidate_canonical: candidate,
      candidate_digest: mediaDigest(original.candidate_digest),
      content_digest: mediaDigest(original.content_digest),
      assignment_digest: mediaDigest(original.assignment_digest),
      backend_generation: mediaUUID(original.backend_generation),
      backend_configuration_digest: mediaDigest(
        original.backend_configuration_digest,
      ),
    });
    parseInitialCpmPhotoCandidate(candidate);
    const document = parseInitialCanonicalText(candidate);
    if (
      !document || typeof document !== "object" || Array.isArray(document) ||
      !("content_canonical" in document) ||
      typeof document.content_canonical !== "string"
    ) throw invalid();
    const content = parseInitialCanonicalText(document.content_canonical);
    if (
      await initialCpmPhotoCandidateDigest(document) !==
        saved.candidate_digest ||
      await initialCpmPhotoContentDigest(content) !== saved.content_digest
    ) throw invalid();
    const request = {
      scan_id: scan,
      initial_recovery: { version: 1, phase, original: saved },
    };
    if (
      new TextEncoder().encode(JSON.stringify(request)).length >
        initialStatusAdmissionRequestBytes
    ) throw invalid();
    return Object.freeze({ phase, scan_id: scan, original: saved });
  }
  const saved = snapshotInitialCompletionAdmission(original);
  const request = {
    scan_id: scan,
    initial_recovery: { version: 1, phase: "completion", original: saved },
  };
  if (
    new TextEncoder().encode(JSON.stringify(request)).length >
      initialStatusCompletionRequestBytes
  ) throw invalid();
  return Object.freeze({ phase: "completion", scan_id: scan, original: saved });
}

/** Trusted private reader context only. The server resolves the immutable full
 * assignment; native receives only the existing validated acknowledgement. */
export async function decodeInitialStatusAdmission(
  value: unknown,
  original: InitialStatusCpmBinding,
) {
  const reply = closed(value, [
    "version",
    "assignment_canonical",
    "acknowledgement",
  ]);
  const assignment = reply.assignment_canonical;
  if (
    reply.version !== 1 || typeof assignment !== "string" ||
    assignment.length > 65536 ||
    new TextEncoder().encode(assignment).length > 65536
  ) throw invalid();
  const acknowledgement = initialCanonicalText(reply.acknowledgement);
  if (new TextEncoder().encode(acknowledgement).length > 8192) throw invalid();
  const saved = await decodeInitialStatusRecoveryRequest({
    scan_id: original.scan_id,
    initial_recovery: { version: 1, phase: "admission", original },
  }, original.owner_id);
  if (saved.phase !== "admission") throw invalid();
  return await decodeCpmCompletionAdmission(
    parseInitialCanonicalText(acknowledgement),
    {
      owner_id: saved.original.owner_id,
      scan_id: saved.scan_id,
      candidate_canonical: saved.original.candidate_canonical,
      assignment_canonical: assignment,
      assignment_digest: saved.original.assignment_digest,
      backend_generation: saved.original.backend_generation,
      backend_configuration_digest: saved.original.backend_configuration_digest,
    },
  );
}
