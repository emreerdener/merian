/** Inactive complete private proof codec. No issuance, funding, dispatch, clock,
 * current selector, storage or recovery authority. Never expose these bytes to clients.
 */
import {
  hex,
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { type InitialSchemaRule, matchesInitialSchema } from "./schema.ts";
import { validateInitialAdmissionMetadata } from "./admissionMetadata.ts";
import schema from "./admitted-proof-schema-v1.json" with { type: "json" };

export const ADMITTED_COMPONENT_LIMITS = Object.freeze(
  {
    candidate: 1048576,
    input: 1048576,
    configuration: 65563,
    funding: 4096,
    outcome: 131072,
    installation: 16384,
    protocol: 16384,
    destination: 16384,
    mapping: 65536,
    media_binding: 16384,
    accounting: 32768,
  } as const,
);
export const ADMITTED_MANIFEST_LIMIT = 8192;
export const ADMITTED_RETAINED_TEXT_LIMIT = 2469915;
export type AdmittedComponent = keyof typeof ADMITTED_COMPONENT_LIMITS;
/** Fixed columns, each containing its original canonical TEXT. No optional roles. */
export type AdmittedProofText = Record<AdmittedComponent | "manifest", string>;
const domains: Record<AdmittedComponent, string> = {
  candidate: "merian.initial-analysis.preparation-candidate.v2\n",
  input: "merian.initial-analysis.input.v1\n",
  configuration: "merian.initial-analysis.configuration.v1\n",
  funding: "merian.initial-analysis.funding.v1\n",
  outcome: "merian.initial-analysis.preparation-execution.outcome.v2\n",
  installation: "merian.initial-analysis.handoff.installation.v1\n",
  protocol: "merian.initial-analysis.handoff.protocol_artifact.v1\n",
  destination: "merian.initial-analysis.handoff.destination_backend.v1\n",
  mapping: "merian.initial-analysis.handoff.mapping.v2\n",
  media_binding: "merian.initial-analysis.handoff.media_binding.v2\n",
  accounting: "merian.initial-analysis.handoff.accounting.v1\n",
};
const bytes = new TextEncoder();
async function digest(prefix: string, text: string): Promise<string> {
  return hex(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        bytes.encode(prefix + text),
      ),
    ),
  );
}
function checkShape(value: unknown, rule: InitialSchemaRule): void {
  if (!matchesInitialSchema(value, rule)) invalidInitialInput();
}
/** Gregorian validation with no Date/epoch conversion or microsecond rounding. */
export function validAdmittedTimestamp(value: unknown): value is string {
  if (typeof value !== "string" || value.length !== 27) return false;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{6})Z$/
    .exec(value);
  if (!match) return false;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map(
    Number,
  );
  if (
    year < 1 || month < 1 || month > 12 || hour > 23 || minute > 59 ||
    second > 59
  ) return false;
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day >= 1 && day <= days[month - 1];
}
function snapshot(value: unknown): AdmittedProofText {
  if (
    !value || typeof value !== "object" ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) invalidInitialInput();
  const keys = [...Object.keys(ADMITTED_COMPONENT_LIMITS), "manifest"];
  const fields = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(value).length !== keys.length) invalidInitialInput();
  // Do not serialize an aggregate: independently valid components can exceed 1 MiB together.
  const result = {} as AdmittedProofText;
  let total = 0;
  for (const key of keys as (keyof AdmittedProofText)[]) {
    const field = fields[key];
    if (
      !field || !field.enumerable || !("value" in field) ||
      typeof field.value !== "string"
    ) invalidInitialInput();
    const limit = key === "manifest"
      ? ADMITTED_MANIFEST_LIMIT
      : ADMITTED_COMPONENT_LIMITS[key];
    const length = bytes.encode(field.value).length;
    if (length > limit) invalidInitialInput();
    parseInitialCanonicalText(field.value);
    result[key] = field.value;
    total += length;
  }
  if (total > ADMITTED_RETAINED_TEXT_LIMIT) invalidInitialInput();
  return result;
}

/** Verifies complete co-retained bytes and internal historical consistency only.
 * Trusted locked owner/funding/expected-transition comparisons, executable archive
 * availability and erasure/terminal fences still belong to the future runtime owner.
 * Callers cannot interpret a successful decode or historical lease as a grant.
 */
export async function validateAdmittedProof(value: unknown): Promise<{
  canonical: AdmittedProofText;
  receiptDigest: string;
}> {
  // Capture every caller byte before the first await, including the full manifest.
  const text = snapshot(value);
  const manifest = JSON.parse(text.manifest);
  const candidate = JSON.parse(text.candidate);
  const input = JSON.parse(text.input);
  const configuration = JSON.parse(text.configuration);
  const funding = JSON.parse(text.funding);
  const outcome = JSON.parse(text.outcome);
  const binding = JSON.parse(text.media_binding);
  const accounting = JSON.parse(text.accounting);
  checkShape(manifest, schema.manifest);
  checkShape(funding, schema.funding);
  checkShape(accounting, schema.accounting);
  if (
    !configuration || typeof configuration !== "object" ||
    Array.isArray(configuration) ||
    Object.keys(configuration).sort().join(",") !== "assignment,version" ||
    configuration.version !== 2
  ) invalidInitialInput();
  const assignment = configuration.assignment;
  // Existing complete validators establish all nested shapes before cross-links are read.
  const metadata = await validateInitialAdmissionMetadata({
    candidate,
    assignment,
    catalog: {
      installation: JSON.parse(text.installation),
      protocol: JSON.parse(text.protocol),
      preparation: outcome?.profile,
      destination: JSON.parse(text.destination),
    },
    outcome,
    originalExpiresAtMs: binding?.phase_window?.original_expires_at_ms,
  }, {
    owner_id: manifest.owner_id,
    scan_id: manifest.scan_id,
    admission_receipt_id: manifest.admission_receipt_id,
  }, {
    phase_window: binding?.phase_window,
    mapping: JSON.parse(text.mapping),
    media_binding: binding,
  });
  if (
    metadata.canonicalInput !== text.input ||
    manifest.route !== input.route || manifest.route !== assignment.route ||
    manifest.input_schema_version !== input.schema_version ||
    manifest.input_schema_version !== candidate.source_plan.schema_version ||
    manifest.descriptions_digest !== metadata.descriptionsDigest ||
    manifest.phase_window_digest !== metadata.phaseWindowDigest ||
    manifest.assets_digest !== assignment.asset_manifest_digest ||
    manifest.authorized_at_ms < binding.phase_window.anchor_ms ||
    manifest.authorized_at_ms >= binding.phase_window.cutoffs.admission
  ) invalidInitialInput();

  for (
    const kind of Object.keys(ADMITTED_COMPONENT_LIMITS) as AdmittedComponent[]
  ) {
    const ref = kind === "mapping" || kind === "media_binding"
      ? manifest.metadata[kind]
      : manifest.proof[kind];
    if (
      ref.byte_count !== bytes.encode(text[kind]).length ||
      ref.digest !== await digest(domains[kind], text[kind])
    ) invalidInitialInput();
  }
  if (
    manifest.metadata_digest !==
      await digest(
        "merian.initial-analysis.handoff.admitted-metadata.v1\n",
        initialCanonicalText(manifest.metadata),
      ) ||
    manifest.proof_digest !==
      await digest(
        "merian.initial-analysis.handoff.admitted-proof.v1\n",
        initialCanonicalText(manifest.proof),
      ) ||
    manifest.assignment_digest !==
      await digest(
        "merian.initial-analysis.assignment.v2\n",
        initialCanonicalText(assignment),
      ) ||
    manifest.assignment_digest !== binding.assignment_digest ||
    manifest.proof.candidate.digest !== assignment.candidate_digest ||
    manifest.proof.input.digest !== binding.submission_digest ||
    manifest.proof.outcome.digest !== binding.outcome_digest ||
    manifest.metadata.mapping.digest !== binding.mapping_digest ||
    manifest.proof.installation.digest !==
      assignment.handoff.installation_digest ||
    manifest.proof.protocol.digest !==
      assignment.handoff.profile.protocol_artifact_digest ||
    manifest.proof.destination.digest !==
      assignment.handoff.profile.destination_backend_config_digest
  ) invalidInitialInput();

  const original = funding.original,
    reservation = accounting.reservation,
    attempt = accounting.attempt;
  if (
    manifest.funding_binding_id !== original.reservation_id ||
    reservation.reservation_id !== original.reservation_id ||
    attempt.reservation_id !== original.reservation_id ||
    reservation.owner_id !== manifest.owner_id ||
    reservation.scan_id !== manifest.scan_id ||
    original.request_id !== manifest.scan_id ||
    original.original_analysis_id !== manifest.scan_id ||
    !validAdmittedTimestamp(reservation.lease_expires_at)
  ) invalidInitialInput();
  for (
    const field of [
      "operation",
      "effective_plan",
      "policy_version",
      "effective_tier",
      "flash_fallback_used",
    ]
  ) {
    if (original[field] !== assignment[field]) invalidInitialInput();
  }
  for (
    const field of [
      "operation",
      "effective_plan",
      "policy_version",
      "provider",
      "binding",
      "processor_permission",
      "input_profile",
      "provider_model",
      "minimum_client_protocol",
      "accepted_client_protocol",
      "minimum_identification_protocol",
      "accepted_identification_protocol",
    ]
  ) {
    if (attempt[field] !== assignment[field]) invalidInitialInput();
  }
  if (
    attempt.model !== assignment.quota_model ||
    original.model !== assignment.effective_model ||
    assignment.effective_model !==
      (assignment.provider_model ?? assignment.quota_model) ||
    assignment.effective_tier !==
      (assignment.effective_plan === "free" ? "free" : "pro") ||
    (assignment.flash_fallback_used && assignment.effective_plan !== "free") ||
    assignment.minimum_client_protocol > assignment.accepted_client_protocol ||
    input.admission.client_protocol !== assignment.accepted_client_protocol ||
    input.admission.identification_protocol !==
      assignment.accepted_identification_protocol ||
    input.admission.expected_processor_permission !==
      assignment.processor_permission
  ) invalidInitialInput();
  if (assignment.provider === "gemini") {
    if (
      assignment.binding !== "gemini_baseline_v1" ||
      assignment.processor_permission !== "google_gemini" ||
      assignment.provider_model !== null ||
      assignment.minimum_identification_protocol !== 0
    ) invalidInitialInput();
  } else if (assignment.provider === "openai") {
    if (
      assignment.binding !== "openai_photo_v1" ||
      assignment.processor_permission !== "openai" ||
      assignment.provider_model !== "gpt-6-sol" ||
      assignment.input_profile !== "multimodal_photo_v1" ||
      assignment.minimum_identification_protocol !== 4
    ) invalidInitialInput();
  } else invalidInitialInput();
  const policy = accounting.charges.policy;
  for (const field of ["operation", "effective_plan", "policy_version"]) {
    if (policy[field] !== original[field]) invalidInitialInput();
  }
  const links = accounting.charges.links;
  if (links.length !== 2 && links.length !== 3) invalidInitialInput();
  const scopes = links.length === 3
    ? ["user_daily", "user_rate", "ip_rate"]
    : ["user_rate", "ip_rate"];
  for (const [index, link] of links.entries()) {
    if (
      link.scope_type !== scopes[index] ||
      link.reservation_id !== original.reservation_id ||
      (link.scope_type === "ip_rate"
        ? !/^[0-9a-f]{64}$/.test(link.scope_key)
        : link.scope_key !== manifest.owner_id) ||
      !link.bucket.replace(/^ +| +$/g, "") ||
      !validAdmittedTimestamp(link.window_start) ||
      (link.scope_type === "user_daily"
        ? link.window_seconds !== 86400
        : link.window_seconds > 3600)
    ) invalidInitialInput();
  }
  const complimentary = accounting.complimentary;
  if (
    (original.complimentary_client_scan_id === null) !==
      (complimentary === null) ||
    (assignment.effective_plan === "pro_complimentary") !==
      (complimentary !== null)
  ) invalidInitialInput();
  if (
    complimentary !== null && (complimentary.owner_id !== manifest.owner_id ||
      complimentary.client_scan_id !== manifest.scan_id ||
      original.complimentary_client_scan_id !== manifest.scan_id)
  ) invalidInitialInput();
  return {
    canonical: text,
    receiptDigest: await digest(
      "merian.initial-analysis.handoff.admitted-receipt.v1\n",
      text.manifest,
    ),
  };
}
