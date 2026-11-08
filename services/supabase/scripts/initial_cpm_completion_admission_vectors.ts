/** Shared synthetic acknowledgement bytes for the native original-admission pin. */
import { initialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import { cpmCompletionAdmissionFixture } from "../functions/_shared/initialAnalysis/fixtures/cpmCompletionAdmission.ts";

export async function cpmCompletionAdmissionVectors() {
  const f = await cpmCompletionAdmissionFixture();
  const assignment = JSON.parse(f.binding.assignment_canonical);
  // Native allocation saves these facts, not the server's full assignment.
  const original = {
    owner_id: f.binding.owner_id,
    scan_id: f.binding.scan_id,
    candidate_canonical: f.binding.candidate_canonical,
    candidate_digest: f.reply.candidate_digest,
    content_digest: assignment.content_digest as string,
    assignment_digest: f.binding.assignment_digest,
    backend_generation: f.binding.backend_generation,
    backend_configuration_digest: f.binding.backend_configuration_digest,
  };
  const documents: { name: string; valid: boolean; acknowledgement: string }[] =
    [];
  function add(name: string, value: unknown, valid = false) {
    documents.push({
      name,
      valid,
      acknowledgement: initialCanonicalText(value),
    });
  }
  add("original_admission", f.reply, true);
  for (const key of Object.keys(f.reply)) {
    const missing: Record<string, unknown> = { ...f.reply };
    delete missing[key];
    add("missing_" + key, missing);
  }
  for (const key of ["owner_id", "scan_id", "backend_generation"] as const) {
    add("foreign_" + key, {
      ...f.reply,
      [key]: "00000000-0000-4000-8000-000000000999",
    });
  }
  for (
    const key of [
      "candidate_digest",
      "assignment_digest",
      "backend_configuration_digest",
    ] as const
  ) add("foreign_" + key, { ...f.reply, [key]: "0".repeat(64) });
  for (
    const [key, value] of Object.entries({
      owner_id: "00000000-0000-4000-8000-000000000999",
      scan_id: "00000000-0000-4000-8000-000000000999",
      input_schema_version: 1,
      submission_digest: "0".repeat(64),
      route: "identify-describe",
      ordered_description_digest: "0".repeat(64),
      ordered_description_count: f.admission.ordered_description_count + 1,
    })
  ) {
    add("admission_" + key, {
      ...f.reply,
      admission_canonical: initialCanonicalText({
        ...f.admission,
        [key]: value,
      }),
    });
  }
  for (const key of Object.keys(f.admission)) {
    const missing: Record<string, unknown> = { ...f.admission };
    delete missing[key];
    add("admission_missing_" + key, {
      ...f.reply,
      admission_canonical: initialCanonicalText(missing),
    });
  }
  add("extra_authority", { ...f.reply, retry: true });
  add("extra_admission", {
    ...f.reply,
    admission_canonical: initialCanonicalText({ ...f.admission, retry: true }),
  });
  add("admission_whitespace", {
    ...f.reply,
    admission_canonical: f.reply.admission_canonical + " ",
  });
  add("admission_over_limit", {
    ...f.reply,
    admission_canonical: "x".repeat(4097),
  });
  add("acknowledgement_over_limit", { ...f.reply, extra: "x".repeat(8193) });
  documents.push({
    name: "acknowledgement_whitespace",
    valid: false,
    acknowledgement: initialCanonicalText(f.reply) + " ",
  });
  return { original, admission: f.reply.admission_canonical, documents };
}
