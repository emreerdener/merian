/** Synthetic original admission facts shared by backend and native byte vectors. */
import { initialCanonicalText } from "../canonical.ts";
import { initialCpmPhotoAssignmentDigest } from "../cpmPhotoAssignment.ts";
import vector from "./cpm-admission-submission-v1.json" with { type: "json" };

export async function cpmCompletionAdmissionFixture() {
  const candidate = JSON.parse(vector.candidate_canonical);
  const assignment = JSON.parse(vector.assignment_canonical);
  const binding = {
    owner_id: "00000000-0000-4000-8000-000000000901",
    scan_id: assignment.scan_id as string,
    candidate_canonical: vector.candidate_canonical,
    assignment_canonical: vector.assignment_canonical,
    assignment_digest: await initialCpmPhotoAssignmentDigest(
      candidate,
      assignment,
    ),
    backend_generation: assignment.preparation.backend_generation as string,
    backend_configuration_digest: "f".repeat(64),
  };
  const admission = {
    version: 1,
    owner_id: binding.owner_id,
    scan_id: binding.scan_id,
    route: assignment.configuration.route as string,
    input_schema_version: 2,
    submission_digest: vector.projection.submission_digest,
    config_digest: "c".repeat(64),
    funding_binding_id: "00000000-0000-4000-8000-000000000902",
    funding_binding_digest: "d".repeat(64),
    funding_binding_version: 1,
    ordered_description_digest: vector.projection.descriptions_digest,
    ordered_description_count: JSON.parse(
      vector.projection.descriptions_canonical,
    ).length as number,
  };
  const reply = {
    version: 1,
    variant: "cpm_completion_admission_v1",
    authority: "none",
    owner_id: binding.owner_id,
    scan_id: binding.scan_id,
    candidate_digest: assignment.candidate_digest as string,
    assignment_digest: binding.assignment_digest,
    backend_generation: binding.backend_generation,
    backend_configuration_digest: binding.backend_configuration_digest,
    admission_receipt_id: "00000000-0000-4000-8000-000000000903",
    admission_receipt_digest: "e".repeat(64),
    admission_canonical: initialCanonicalText(admission),
  };
  return { binding, admission, reply };
}
