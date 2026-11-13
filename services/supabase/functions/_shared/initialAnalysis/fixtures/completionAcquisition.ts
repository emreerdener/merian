import { captureInitialResult } from "../resultEvidence.ts";
/** Synthetic original acquisition shared by wire and private-reader tests. */
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "../canonical.ts";
import {
  binding,
  capture,
  data,
  id,
  other,
  outcome,
} from "./resultEvidence.ts";
import { projection, receipt } from "./completionDocuments.ts";
import {
  type InitialCompletionAdmission,
  snapshotInitialCompletionAdmission,
} from "../completionAcquisition.ts";
import { transformInitialResult } from "../resultEncoding.ts";
import { provenanceContractV1 } from "../resultSchemaV1.ts";
export async function completionAcquisitionFixture(
  cpm = true,
  original?: InitialCompletionAdmission,
  reasoning?: string,
) {
  const body = data();
  if (original) body.scan_id = original.scan_id;
  if (reasoning !== undefined) body.ai_reasoning = reasoning;
  const evidence = original
    ? await captureInitialResult({
      binding: { ...binding, ...original },
      invocationId: id,
      resultEvidenceId: other,
      outcome,
      data: body,
    })
    : await capture(body);
  const p = projection(cpm);
  Object.assign(p, {
    owner_id: evidence.reference.owner_id,
    scan_id: evidence.reference.scan_id,
    result_evidence_id: evidence.reference.result_evidence_id,
    result_digest: evidence.result_digest,
  });
  p.capture_context.submission_digest = evidence.reference.submission_digest;
  const r = await receipt(p);
  Object.assign(r, {
    owner_id: p.owner_id,
    scan_id: p.scan_id,
    operation_id: p.scan_id,
    result_evidence_id: p.result_evidence_id,
    result_digest: p.result_digest,
    config_digest: evidence.reference.config_digest,
    funding_binding_id: binding.funding_binding_id,
    funding_binding_digest: evidence.reference.funding_binding_digest,
  });
  if (original) Object.assign(r, original);
  const admission = snapshotInitialCompletionAdmission({
    version: 1,
    owner_id: r.owner_id,
    scan_id: r.scan_id,
    route: r.route,
    input_schema_version: r.input_schema_version,
    submission_digest: r.submission_digest,
    config_digest: r.config_digest,
    funding_binding_id: r.funding_binding_id,
    funding_binding_digest: r.funding_binding_digest,
    funding_binding_version: r.funding_binding_version,
    ordered_description_digest: r.ordered_description_digest,
    ordered_description_count: r.ordered_description_count,
  });
  const delivery = {
    version: 1,
    outcome: "found",
    reference: evidence.reference,
    completion: {
      receipt_canonical: initialCanonicalText(r),
      projection_canonical: initialCanonicalText(p),
    },
    result: evidence,
  };
  return {
    admission,
    evidence,
    delivery,
    reply: {
      version: 1,
      outcome: "found",
      admission_canonical: initialCanonicalText(admission),
      reference: evidence.reference,
      result_digest: evidence.result_digest,
      original_provenance: transformInitialResult(
        provenanceContractV1,
        parseInitialCanonicalText(evidence.provenance_canonical),
        "decode",
      ),
      delivery,
    },
  };
}
