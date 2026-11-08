/** Inactive authenticated status projection of existing validated acquisition
 * facts. Canonical inner documents are unchanged; no new result interpretation. */
import schema from "./completion-status-response-schema-v1.json" with {
  type: "json",
};
import { initialCanonicalText } from "./canonical.ts";
import {
  type decodeInitialCompletionAcquisition,
  type InitialCompletionAdmission,
  snapshotInitialCompletionAdmission,
} from "./completionAcquisition.ts";
import { matchesInitialSchema } from "./schema.ts";

export const initialCompletionStatusResponseBytes = 2541568;
type Acquisition = Awaited<
  ReturnType<typeof decodeInitialCompletionAcquisition>
>;
const invalid = () => new Error("initial_completion_status_response_invalid");

/** Only the fixed validated reader supplies acquisition. The canonical outer
 * JSON contains bounded scalar fields, avoiding ordinary JSON decoding of the
 * retained result and keeping literal FEFF/normalization-sensitive bytes exact.
 * The ordinary IC-1 canonical parser/encoder keeps its unchanged 1MiB ceiling. */
export function encodeInitialCompletionStatus(
  original: InitialCompletionAdmission,
  acquisition: Acquisition,
): Uint8Array {
  const admission = initialCanonicalText(
    snapshotInitialCompletionAdmission(original),
  );
  if (
    acquisition && initialCanonicalText(acquisition.admission) !== admission
  ) throw invalid();
  const response = {
    version: 1,
    outcome: acquisition ? "found" : "pending",
    admission_canonical: admission,
    reference_canonical: acquisition
      ? initialCanonicalText(acquisition.reference)
      : null,
    original_provenance_canonical: acquisition?.original_provenance_canonical ??
      null,
    receipt_canonical: acquisition?.delivery.receipt_canonical ?? null,
    projection_canonical: acquisition?.delivery.projection_canonical ?? null,
    result_canonical: acquisition?.delivery.result.result_canonical ?? null,
    result_digest: acquisition?.result_digest ?? null,
    provenance_digest: acquisition?.delivery.result.provenance_digest ?? null,
  };
  if (!matchesInitialSchema(response, schema)) throw invalid();
  // All keys are fixed and all values are scalar. Escape each string once;
  // sorting fixed ASCII keys produces the same canonical grammar as IC-1.
  const text = "{" +
    Object.entries(response).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
      .map(([key, value]) => JSON.stringify(key) + ":" + JSON.stringify(value))
      .join(",") +
    "}";
  const bytes = new TextEncoder().encode(text);
  if (bytes.length > initialCompletionStatusResponseBytes) throw invalid();
  return bytes;
}
