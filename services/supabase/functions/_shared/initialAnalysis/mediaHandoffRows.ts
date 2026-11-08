/** Private local-adapter row decoding. Canonical consistency is not SQL/storage
 * authority; callers must use the fixed trusted bridge and fresh loaders. */
import {
  ADMITTED_COMPONENT_LIMITS,
  ADMITTED_MANIFEST_LIMIT,
  type AdmittedProofText,
  validateAdmittedProof,
} from "./admittedProof.ts";
import {
  type AdmissionDestinationMapping,
  type AdmissionMediaBinding,
} from "./admissionMetadata.ts";
import {
  type InitialAdmissionRecoveryResponse,
  validateInitialAdmissionRecoveryResponse,
} from "./admissionRecoveryResponse.ts";
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { type InitialHandoffProfile } from "./handoffProfile.ts";
import {
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaUUID,
} from "./mediaBinding.ts";
import {
  type MediaTransferReceiptV1,
  type MediaVerificationClaimV2,
  type MediaVerificationReceiptV2,
  validateMediaTransferReceipt,
  validateMediaVerificationClaim,
  validateMediaVerificationReceipt,
} from "./mediaHandoffProof.ts";
import {
  decodeHandoffDestinationBackend,
  decodeHandoffSourceBackend,
} from "./mediaHandoffStorage.ts";

export interface HandoffIdentity {
  owner_id: string;
  scan_id: string;
  admission_receipt_digest: string;
}
export interface HandoffProgress {
  scan_id: string;
  owner_id: string;
  admission_receipt_digest: string;
  copy_adapter_digest: string;
  started_at_ms: number;
  completed_objects: string;
  last_object_at_ms: number | null;
  completed_at_ms: number | null;
}
export interface HandoffDocument<T> {
  canonical: string;
  digest: string;
  value: T;
}
export interface HandoffRows {
  identity: Readonly<HandoffIdentity>;
  original: Readonly<AdmittedProofText>;
  binding: AdmissionMediaBinding;
  mapping: AdmissionDestinationMapping;
  handoff: InitialHandoffProfile;
  progress: Readonly<HandoffProgress> | null;
  claim: HandoffDocument<MediaVerificationClaimV2> | null;
  verification: HandoffDocument<MediaVerificationReceiptV2> | null;
  transfer: HandoffDocument<MediaTransferReceiptV1> | null;
  observedAtMs: number;
}
const encoder = new TextEncoder();
function freeze<T>(value: T): T {
  if (value !== null && typeof value === "object") {
    for (const member of Object.values(value)) freeze(member);
    Object.freeze(value);
  }
  return value;
}
function text(value: unknown, limit: number): string {
  if (
    typeof value !== "string" || value.length > limit ||
    encoder.encode(value).length > limit
  ) throw initialMediaUnavailable();
  return value;
}
function bounded(value: unknown, limit: number): Record<string, unknown> {
  return JSON.parse(text(initialCanonicalText(value), limit));
}
function time(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw initialMediaUnavailable();
  }
  return value;
}
export function handoffIdentity(
  value: HandoffIdentity,
): Readonly<HandoffIdentity> {
  const v = mediaRecord(value, [
    "owner_id",
    "scan_id",
    "admission_receipt_digest",
  ]);
  return Object.freeze({
    owner_id: mediaUUID(v.owner_id),
    scan_id: mediaUUID(v.scan_id),
    admission_receipt_digest: mediaDigest(v.admission_receipt_digest),
  });
}
function scope(
  row: Record<string, unknown>,
  identity: Readonly<HandoffIdentity>,
): void {
  if (row.owner_id !== identity.owner_id || row.scan_id !== identity.scan_id) {
    throw initialMediaUnavailable();
  }
}
interface Snapshot {
  original: AdmittedProofText;
  admissionID: string;
  digest: string;
  progress: Record<string, unknown> | null;
  claim: Record<string, unknown> | null;
  verification: Record<string, unknown> | null;
  transfer: Record<string, unknown> | null;
  observed: number;
}
function snapshot(
  raw: Record<string, unknown>,
  identity: Readonly<HandoffIdentity>,
  state: boolean,
): Snapshot {
  const keys = {
    ...ADMITTED_COMPONENT_LIMITS,
    manifest: ADMITTED_MANIFEST_LIMIT,
  };
  const a = mediaRecord(raw.admission, [
    ...Object.keys(keys),
    "owner_id",
    "scan_id",
    "admission_receipt_id",
    "receipt_digest",
  ]);
  scope(a, identity);
  const original = {} as AdmittedProofText;
  for (const [key, limit] of Object.entries(keys)) {
    original[key as keyof AdmittedProofText] = text(a[key], limit);
  }
  return {
    original,
    admissionID: mediaUUID(a.admission_receipt_id),
    digest: mediaDigest(a.receipt_digest),
    progress: raw.progress === null ? null : bounded(raw.progress, 12_288),
    claim: raw.claim === null ? null : bounded(raw.claim, 65_536),
    verification: !state || raw.verification === null
      ? null
      : bounded(raw.verification, 131_072),
    transfer: !state || raw.transfer === null
      ? null
      : bounded(raw.transfer, 196_608),
    observed: time(raw.observed_at_ms),
  };
}
function document(
  row: Record<string, unknown> | null,
  identity: Readonly<HandoffIdentity>,
  claim: boolean,
  limit: number,
): HandoffDocument<unknown> | null {
  if (row === null) return null;
  const field = claim ? "claim" : "receipt",
    digest = claim ? "claim_digest" : "receipt_digest";
  mediaRecord(row, ["owner_id", "scan_id", field, digest]);
  scope(row, identity);
  const canonical = text(row[field], limit);
  return {
    canonical,
    digest: mediaDigest(row[digest]),
    value: parseInitialCanonicalText(canonical),
  };
}
async function core(
  s: Snapshot,
  identity: Readonly<HandoffIdentity>,
): Promise<HandoffRows> {
  if (s.digest !== identity.admission_receipt_digest) {
    throw initialMediaUnavailable();
  }
  const original = await validateAdmittedProof(s.original);
  if (original.receiptDigest !== s.digest) throw initialMediaUnavailable();
  const binding: AdmissionMediaBinding = JSON.parse(
    original.canonical.media_binding,
  );
  const mapping: AdmissionDestinationMapping = JSON.parse(
    original.canonical.mapping,
  );
  const handoff: InitialHandoffProfile =
    JSON.parse(original.canonical.configuration).assignment.handoff.profile;
  scope(binding as unknown as Record<string, unknown>, identity);
  if (binding.admission_receipt_id !== s.admissionID) {
    throw initialMediaUnavailable();
  }
  const admittedAt: number =
    JSON.parse(original.canonical.manifest).authorized_at_ms;
  let progress: HandoffProgress | null = null;
  if (s.progress !== null) {
    const p = mediaRecord(s.progress, [
      "scan_id",
      "owner_id",
      "admission_receipt_digest",
      "copy_adapter_digest",
      "started_at_ms",
      "completed_objects",
      "last_object_at_ms",
      "completed_at_ms",
    ]);
    scope(p, identity);
    if (
      p.admission_receipt_digest !== s.digest ||
      p.copy_adapter_digest !== handoff.copy_adapter_digest
    ) throw initialMediaUnavailable();
    const started = time(p.started_at_ms),
      last = p.last_object_at_ms === null ? null : time(p.last_object_at_ms),
      completed = p.completed_at_ms === null ? null : time(p.completed_at_ms);
    const objectsText = text(p.completed_objects, 8192),
      objects = parseInitialCanonicalText(objectsText);
    if (
      !Array.isArray(objects) || objects.length > mapping.objects.length ||
      started < admittedAt || started >= binding.phase_window.cutoffs.copy
    ) throw initialMediaUnavailable();
    let previous = "";
    for (const object of objects) {
      const o = mediaRecord(object, [
        "object_id",
        "backend_generation",
        "byte_count",
        "sha256",
        "content_type",
      ]);
      const id = mediaUUID(o.object_id),
        expected = mapping.objects.find((entry) => entry.object_id === id);
      if (
        id <= previous || !expected ||
        initialCanonicalText(o) !==
          initialCanonicalText({
            object_id: id,
            backend_generation: mapping.destination_backend_generation,
            ...expected.bytes,
          })
      ) throw initialMediaUnavailable();
      previous = id;
    }
    if (
      objects.length === 0
        ? last !== null || completed !== null
        : last === null || last < started ||
          last >= binding.phase_window.cutoffs.copy
    ) throw initialMediaUnavailable();
    if (
      completed !== null &&
      (last === null || completed < last ||
        completed >= binding.phase_window.cutoffs.copy ||
        objects.length !== mapping.objects.length)
    ) throw initialMediaUnavailable();
    progress = p as unknown as HandoffProgress;
  }
  const claim = document(s.claim, identity, true, 32_768) as
    | HandoffDocument<MediaVerificationClaimV2>
    | null;
  const verification = document(s.verification, identity, false, 65_536) as
    | HandoffDocument<MediaVerificationReceiptV2>
    | null;
  const transfer = document(s.transfer, identity, false, 98_304) as
    | HandoffDocument<MediaTransferReceiptV1>
    | null;
  if (claim !== null) {
    if (
      progress?.completed_at_ms == null ||
      (await validateMediaVerificationClaim(original.canonical, claim.value))
          .digest !== claim.digest ||
      claim.value.issued_at_ms < progress.completed_at_ms
    ) throw initialMediaUnavailable();
  }
  if (
    verification !== null &&
    (claim === null ||
      (await validateMediaVerificationReceipt(
          original.canonical,
          claim.value,
          verification.value,
        )).digest !== verification.digest)
  ) throw initialMediaUnavailable();
  if (
    transfer !== null &&
    (claim === null || verification === null ||
      (await validateMediaTransferReceipt(
          original.canonical,
          claim.value,
          verification.value,
          transfer.value,
        )).digest !== transfer.digest)
  ) throw initialMediaUnavailable();
  if (
    s.observed < Math.max(
      admittedAt,
      progress?.started_at_ms ?? 0,
      progress?.last_object_at_ms ?? 0,
      progress?.completed_at_ms ?? 0,
      claim?.value.issued_at_ms ?? 0,
      verification?.value.authorized_at_ms ?? 0,
      transfer?.value.authorized_at_ms ?? 0,
    )
  ) throw initialMediaUnavailable();
  return freeze({
    identity,
    original: original.canonical,
    binding,
    mapping,
    handoff,
    progress,
    claim,
    verification,
    transfer,
    observedAtMs: s.observed,
  });
}
export async function decodeHandoffState(
  value: unknown,
  requested: HandoffIdentity,
): Promise<HandoffRows> {
  const identity = handoffIdentity(requested),
    raw = mediaRecord(value, [
      "response",
      "admission",
      "progress",
      "claim",
      "verification",
      "transfer",
      "observed_at_ms",
    ]);
  // Snapshot every row before hashing the admitted proof can yield.
  const s = snapshot(raw, identity, true),
    response = bounded(raw.response, 32768);
  const rows = await core(s, identity);
  const r = JSON.parse(
    await validateInitialAdmissionRecoveryResponse(response),
  ) as InitialAdmissionRecoveryResponse;
  if (
    r.outcome === "held" ||
    r.admission_receipt_digest !== identity.admission_receipt_digest ||
    initialCanonicalText(r.binding) !== rows.original.media_binding ||
    (rows.transfer !== null
      ? r.outcome !== "transferred" ||
        r.transfer_receipt_digest !== rows.transfer.digest
      : r.outcome !== "admitted")
  ) throw initialMediaUnavailable();
  if (r.outcome === "admitted") {
    const phase = rows.verification !== null
      ? "transfer"
      : rows.claim !== null || rows.progress?.completed_at_ms != null
      ? "verification"
      : "copy";
    const cutoff = rows.verification !== null
      ? "transfer"
      : rows.claim !== null
      ? "verification_settlement"
      : rows.progress?.completed_at_ms != null
      ? "verification_claim"
      : "copy";
    if (
      r.phase !==
        (rows.observedAtMs >= rows.binding.phase_window.cutoffs[cutoff]
          ? "expired"
          : phase)
    ) throw initialMediaUnavailable();
  }
  return rows;
}
export async function decodeHandoffIO(
  value: unknown,
  requested: HandoffIdentity,
  phase: "copy" | "verification",
  expectedClaim: string | null,
) {
  const identity = handoffIdentity(requested),
    raw = mediaRecord(value, [
      "admission",
      "progress",
      "claim",
      "source_backend",
      "destination_backend",
      "observed_at_ms",
    ]);
  const s = snapshot(raw, identity, false),
    source = bounded(raw.source_backend, 16384),
    destination = bounded(raw.destination_backend, 16384);
  const rows = await core(s, identity);
  const p = rows.progress, claim = rows.claim;
  if (phase !== "copy" && phase !== "verification") {
    throw initialMediaUnavailable();
  }
  if (
    p === null ||
    (phase === "copy"
      ? expectedClaim !== null || p.completed_at_ms !== null ||
        claim !== null ||
        JSON.parse(p.completed_objects).length === rows.mapping.objects.length
      : p.completed_at_ms === null || claim === null ||
        claim.value.claim_token !== expectedClaim)
  ) throw initialMediaUnavailable();
  if (
    rows.observedAtMs <
      Math.max(
        p.started_at_ms,
        p.last_object_at_ms ?? 0,
        p.completed_at_ms ?? 0,
        claim?.value.issued_at_ms ?? 0,
      ) || rows.observedAtMs >= rows.binding.phase_window.cutoffs[phase]
  ) throw initialMediaUnavailable();
  if (initialCanonicalText(destination) !== rows.original.destination) {
    throw initialMediaUnavailable();
  }
  const sourceBackend = await decodeHandoffSourceBackend(
    source,
    rows.handoff.source_backend_generation,
    rows.handoff.source_backend_config_digest,
  );
  const destinationBackend = decodeHandoffDestinationBackend(
    destination,
    rows.handoff.destination_backend_generation,
  );
  return Object.freeze({ rows, sourceBackend, destinationBackend });
}
