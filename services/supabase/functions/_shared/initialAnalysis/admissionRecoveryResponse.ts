/** Inactive status metadata. Validation grants no I/O or lifecycle authority. */
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema } from "./schema.ts";
import {
  type AdmissionMediaBinding,
  admissionMetadataDigest,
} from "./admissionMetadata.ts";
import { HANDOFF_PHASES } from "./handoffProfile.ts";
import schema from "./admission-recovery-response-schema-v2.json" with {
  type: "json",
};

export type InitialAdmissionRecoveryResponse =
  | {
    version: 2;
    outcome: "admitted";
    authority: "none";
    scan_id: string;
    admission_receipt_digest: string;
    binding: AdmissionMediaBinding;
    phase: "copy" | "verification" | "transfer" | "expired";
  }
  | {
    version: 2;
    outcome: "transferred";
    authority: "none";
    scan_id: string;
    admission_receipt_digest: string;
    transfer_receipt_digest: string;
    binding: AdmissionMediaBinding;
  }
  | {
    version: 2;
    outcome: "held";
    authority: "none";
    reason: "already_transferred";
    transfer_receipt_digest: string;
  };

/** Decode only after transport correlation with the original operation. This
 * checks closed shape and internal consistency, not stored receipt existence,
 * live ownership, cancellation, transfer proof, or current phase eligibility.
 * No local clock can upgrade this reply into permission for another action.
 */
export async function validateInitialAdmissionRecoveryResponse(
  value: unknown,
): Promise<string> {
  // Snapshot before the first await; return these exact accepted bytes.
  const text = initialCanonicalText(value);
  const parsed = parseInitialCanonicalText(text);
  if (
    new TextEncoder().encode(text).length > 32768 ||
    !Object.values(schema).some((rule) => matchesInitialSchema(parsed, rule))
  ) invalidInitialInput();
  const response = parsed as InitialAdmissionRecoveryResponse;
  if (response.outcome === "held") return text;
  const binding = response.binding, window = binding.phase_window;
  if (
    new TextEncoder().encode(initialCanonicalText(binding)).length > 16384 ||
    response.scan_id !== binding.scan_id ||
    binding.owner_id !== window.owner_id ||
    binding.scan_id !== window.scan_id ||
    binding.admission_receipt_id !== window.admission_receipt_id
  ) invalidInitialInput();
  let previous = window.anchor_ms;
  for (const phase of HANDOFF_PHASES) {
    const cutoff = window.cutoffs[phase];
    if (cutoff <= previous) invalidInitialInput();
    previous = cutoff;
  }
  if (
    previous >= window.original_expires_at_ms ||
    binding.phase_window_digest !== await admissionMetadataDigest(
        "phase_window",
        initialCanonicalText(window),
      )
  ) invalidInitialInput();
  return text;
}
