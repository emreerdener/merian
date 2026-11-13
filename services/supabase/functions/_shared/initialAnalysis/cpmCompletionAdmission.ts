/** Original admission acknowledgement from the private CPM read owner. This is
 * neither the older boolean recovery reply nor authority to admit or execute. */
import schema from "./cpm-completion-admission-schema-v1.json" with {
  type: "json",
};
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { initialCpmPhotoAssignmentDigest } from "./cpmPhotoAssignment.ts";
import type { CpmAdmissionIdentity } from "./cpmPhotoAdmission.ts";
import { snapshotInitialCompletionAdmission } from "./completionAcquisition.ts";
import {
  initialMediaHash,
  mediaDigest,
  mediaRecord,
  mediaUUID,
} from "./mediaBinding.ts";
import { matchesInitialSchema } from "./schema.ts";

export interface CpmCompletionAdmissionBinding extends CpmAdmissionIdentity {
  readonly backend_generation: string;
  readonly backend_configuration_digest: string;
}
const invalid = () => new Error("initial_cpm_completion_admission_invalid");
const encoder = new TextEncoder();
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw invalid();
  }
  return value as Record<string, unknown>;
}
function parsedRecord(text: string) {
  return record(parseInitialCanonicalText(text));
}

/** Snapshot before awaiting, including the exact saved allocation and backend
 * binding. Configuration/funding are never selected from current account state. */
export async function snapshotCpmCompletionAdmissionBinding(
  value: CpmCompletionAdmissionBinding,
) {
  const r = mediaRecord(value, [
    "owner_id",
    "scan_id",
    "candidate_canonical",
    "assignment_canonical",
    "assignment_digest",
    "backend_generation",
    "backend_configuration_digest",
  ]);
  if (
    Object.values(Object.getOwnPropertyDescriptors(value)).some((d) =>
      !("value" in d)
    )
  ) throw invalid();
  const candidate = r.candidate_canonical, assignment = r.assignment_canonical;
  if (
    typeof candidate !== "string" || typeof assignment !== "string" ||
    encoder.encode(candidate).length > 1048576 ||
    encoder.encode(assignment).length > 65536
  ) throw invalid();
  const copy = Object.freeze({
    owner_id: mediaUUID(r.owner_id),
    scan_id: mediaUUID(r.scan_id),
    candidate_canonical: candidate,
    assignment_canonical: assignment,
    assignment_digest: mediaDigest(r.assignment_digest),
    backend_generation: mediaUUID(r.backend_generation),
    backend_configuration_digest: mediaDigest(r.backend_configuration_digest),
  });
  const a = parsedRecord(assignment),
    c = parseInitialCanonicalText(candidate);
  if (
    await initialCpmPhotoAssignmentDigest(c, a) !== copy.assignment_digest ||
    a.scan_id !== copy.scan_id ||
    record(a.preparation).backend_generation !==
      copy.backend_generation
  ) throw invalid();
  return copy;
}

/** Only the authenticated private SQL read supplies the acknowledgement. The
 * caller must durably pin these original bytes through its existing fenced owner
 * before requesting completion; this decoder installs no native persistence. */
export async function decodeCpmCompletionAdmission(
  value: unknown,
  original: CpmCompletionAdmissionBinding,
) {
  return (await bindCpmCompletionAdmission(value, original)).receipt;
}

/** Keep the checked original with its receipt for server-side composition.
 * Existing status consumers continue to receive only their original projection. */
export async function bindCpmCompletionAdmission(
  value: unknown,
  original: CpmCompletionAdmissionBinding,
) {
  // Freeze the reply before request validation yields to the digest worker.
  const canonical = initialCanonicalText(value);
  if (encoder.encode(canonical).length > 8192) throw invalid();
  const r = parsedRecord(canonical);
  if (!matchesInitialSchema(r, schema)) throw invalid();
  const saved = await snapshotCpmCompletionAdmissionBinding(original);
  const assignment = parsedRecord(saved.assignment_canonical);
  for (
    const key of [
      "owner_id",
      "scan_id",
      "assignment_digest",
      "backend_generation",
      "backend_configuration_digest",
    ] as const
  ) {
    if (r[key] !== saved[key]) throw invalid();
  }
  if (
    r.candidate_digest !== assignment.candidate_digest ||
    typeof r.admission_canonical !== "string"
  ) throw invalid();
  const admission = snapshotInitialCompletionAdmission(
    parseInitialCanonicalText(r.admission_canonical),
  );
  const candidate = parsedRecord(saved.candidate_canonical);
  if (typeof candidate.content_canonical !== "string") throw invalid();
  const content = parsedRecord(candidate.content_canonical);
  if (!Array.isArray(content.contexts)) throw invalid();
  const descriptionDigest = await initialMediaHash(encoder.encode(
    "merian.initial-analysis.cpm-photo-contexts.v1\n" +
      initialCanonicalText(content.contexts),
  ));
  if (
    admission.owner_id !== saved.owner_id ||
    admission.scan_id !== saved.scan_id ||
    admission.input_schema_version !== 2 ||
    admission.submission_digest !== assignment.content_digest ||
    admission.route !==
      record(assignment.configuration).route ||
    admission.ordered_description_count !== content.contexts.length ||
    admission.ordered_description_digest !== descriptionDigest
  ) throw invalid();
  const receipt = Object.freeze({
    canonical,
    admission_canonical: r.admission_canonical,
    admission,
    admission_receipt_id: mediaUUID(r.admission_receipt_id),
    admission_receipt_digest: mediaDigest(r.admission_receipt_digest),
  });
  return Object.freeze({ original: saved, receipt });
}
