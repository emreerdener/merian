/** Inactive native storage representation; no result or write authority. */
import { initialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import { initialMediaHash } from "../functions/_shared/initialAnalysis/mediaBinding.ts";
import { cpmCompletionAdmissionFixture } from "../functions/_shared/initialAnalysis/fixtures/cpmCompletionAdmission.ts";
import { capture } from "../functions/_shared/initialAnalysis/fixtures/resultEvidence.ts";
import {
  id,
  projection,
  receipt,
} from "../functions/_shared/initialAnalysis/fixtures/completionDocuments.ts";
import { snapshotInitialCompletionDocuments } from "../functions/_shared/initialAnalysis/completionContract.ts";

const bytes = new TextEncoder();
const base64 = (data: Uint8Array) =>
  btoa(Array.from(data, (n) => String.fromCharCode(n)).join(""));
export async function completionRecoveryVector() {
  const original = await cpmCompletionAdmissionFixture();
  const p = projection();
  p.owner_id = original.admission.owner_id;
  p.scan_id = original.admission.scan_id;
  p.capture_context.submission_digest = original.admission.submission_digest;
  const r = {
    ...await receipt(p),
    ...original.admission,
    operation_id: p.scan_id,
  };
  await snapshotInitialCompletionDocuments(r, p);
  const reference = {
    owner_id: r.owner_id,
    scan_id: r.scan_id,
    invocation_id: id(999),
    result_evidence_id: r.result_evidence_id,
    submission_digest: r.submission_digest,
    config_digest: r.config_digest,
    funding_binding_digest: r.funding_binding_digest,
  };
  const provenance = (await capture()).provenance_canonical;
  const receiptText = initialCanonicalText(r),
    projectionText = initialCanonicalText(p);
  const record = {
    version: 1,
    state: "completion_pinned",
    admission_sha256: await initialMediaHash(
      bytes.encode(initialCanonicalText(original.reply)),
    ),
    reference,
    result_digest: r.result_digest,
    provenance_digest: await initialMediaHash(
      bytes.encode(
        `merian.initial-analysis.result-provenance.v1\n${provenance}`,
      ),
    ),
    provenance_base64: base64(bytes.encode(provenance)),
    receipt_base64: base64(bytes.encode(receiptText)),
    projection_base64: base64(bytes.encode(projectionText)),
  };
  const maximum = {
    ...record,
    provenance_base64: base64(new Uint8Array(65_536)),
    receipt_base64: base64(new Uint8Array(16_384)),
    projection_base64: base64(new Uint8Array(65_536)),
  };
  return {
    reference: initialCanonicalText(reference),
    provenance,
    receipt: receiptText,
    projection: projectionText,
    encoded: initialCanonicalText(record),
    maximum_bytes: bytes.encode(initialCanonicalText(maximum)).length,
  };
}
