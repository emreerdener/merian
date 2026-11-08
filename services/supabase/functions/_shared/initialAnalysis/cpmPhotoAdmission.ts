/** Private, uninstalled CPM verification-to-admission coordinator.
 * The bridge is trusted server composition, never client callbacks/proof. Its
 * structural verifier and atomic SQL admission implementation are not installed.
 * This is not the already-admitted M2 verification path or inference authority. */
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { parseInitialCpmPhotoCandidate } from "./cpmPhotoCandidate.ts";
import { initialCpmPhotoAssignmentDigest } from "./cpmPhotoAssignment.ts";
import { cpmClosureTimestamp } from "./cpmPhotoWriteClosure.ts";
import {
  initialMediaHash,
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaUUID,
} from "./mediaBinding.ts";
import {
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  initialRemainingDeadline,
} from "./transport.ts";

export interface CpmAdmissionIdentity {
  owner_id: string;
  scan_id: string;
  candidate_canonical: string;
  assignment_canonical: string;
  assignment_digest: string;
}
export interface CpmVerificationStart extends CpmAdmissionIdentity {
  attempt_id: string;
  snapshot_canonical: string;
  snapshot_digest: string;
}
export interface CpmAdmissionEvidence extends CpmVerificationStart {
  /** Prepared CPM branch only. SQL must derive these again from locked saved
   * rows, never accept caller-selected input, versions or description rewrites. */
  input_schema_version: 2;
  binding_version: 4;
  submission_canonical: string;
  submission_digest: string;
  descriptions_canonical: string;
  descriptions_digest: string;
  verification_canonical: string;
  verification_digest: string;
}
export interface CpmPhotoAdmissionBridge {
  /** False means conclusively absent; unknown reads MUST reject, never return
   * false. Fixed database owner validates the exact retained receipt, identity and
   * account/deletion fences. True means a committed admission was reconciled;
   * it grants no new verification, dispatch or provider execution authority. */
  recover(
    identity: Readonly<CpmAdmissionIdentity>,
    signal: AbortSignal,
  ): Promise<boolean>;
  /** Return ONLY after committing begin_initial_cpm_photo_verification. An
   * uncertain commit must throw or return held, never reconstruct started. */
  begin(
    identity: Readonly<CpmAdmissionIdentity>,
    signal: AbortSignal,
  ): Promise<unknown>;
  /** Trusted complete-cohort structural verifier bound to the saved build and
   * profile. It owns bounded physical acquisition/cancellation and release;
   * this orchestration alone does not qualify those resource obligations.
   * Recheck current account/deletion/retirement and exact original facts before
   * external reads; the committed start is not a lease against retirement. */
  verify(
    start: Readonly<CpmVerificationStart>,
    signal: AbortSignal,
  ): Promise<unknown>;
  /** One atomic existing-stage/funding/retained-capacity/C1 transaction. SQL
   * rechecks the original start, cohort, deadline, eligibility and saved rows.
   * Resolve only after commit; an uncertain response throws. No successor. */
  admit(
    evidence: Readonly<CpmAdmissionEvidence>,
    signal: AbortSignal,
  ): Promise<void>;
}
type Member = {
  role: {
    object_id: string;
    photo_ordinal: number;
    role: string;
    declaration: {
      byte_count: number;
      sha256: string;
      declared_content_type: string;
    };
  };
};
type Snapshot = {
  members: Member[];
  profile_digest: string;
  verifier_build_digest: string;
};
const held = Object.freeze(
  { version: 1, outcome: "held", authority: "none" } as const,
);
const admitted = Object.freeze(
  { version: 1, outcome: "admitted", authority: "none" } as const,
);
function bounded(value: unknown): string {
  const text = initialCanonicalText(value);
  if (new TextEncoder().encode(text).length > 65536) {
    throw initialMediaUnavailable();
  }
  return text;
}
function same(a: unknown, b: unknown): boolean {
  return initialCanonicalText(a) === initialCanonicalText(b);
}
async function digest(domain: string, text: string): Promise<string> {
  return await initialMediaHash(new TextEncoder().encode(`${domain}\n${text}`));
}
async function decodeStart(
  value: unknown,
  identity: Readonly<CpmAdmissionIdentity>,
) {
  const r = mediaRecord(JSON.parse(bounded(value)), [
    "version",
    "outcome",
    "attempt_id",
    "snapshot_canonical",
    "snapshot_digest",
  ]);
  if (
    r.version !== 1 || r.outcome !== "started" ||
    typeof r.snapshot_canonical !== "string"
  ) throw initialMediaUnavailable();
  mediaUUID(r.attempt_id);
  mediaDigest(r.snapshot_digest);
  const s = mediaRecord(parseInitialCanonicalText(r.snapshot_canonical), [
    "version",
    "owner_id",
    "scan_id",
    "candidate_digest",
    "content_digest",
    "assignment_digest",
    "profile_digest",
    "verifier_build_digest",
    "backend_generation",
    "backend_configuration_digest",
    "original_expires_at_ms",
    "members",
  ]);
  const a = JSON.parse(identity.assignment_canonical), p = a.preparation;
  if (
    s.version !== 1 || s.owner_id !== identity.owner_id ||
    s.scan_id !== identity.scan_id ||
    s.candidate_digest !== a.candidate_digest ||
    s.content_digest !== a.content_digest ||
    s.assignment_digest !== identity.assignment_digest ||
    s.profile_digest !== p.profile_digest ||
    s.verifier_build_digest !== p.verifier_build_digest ||
    s.backend_generation !== p.backend_generation ||
    s.original_expires_at_ms !== a.expires_at_ms || !Array.isArray(s.members) ||
    s.members.length !== p.role_mapping.length
  ) throw initialMediaUnavailable();
  mediaDigest(s.backend_configuration_digest);
  const attempts = new Set<string>();
  for (const [index, item] of s.members.entries()) {
    const m = mediaRecord(item, ["role", "attempt", "closure"]);
    if (!same(m.role, p.role_mapping[index])) throw initialMediaUnavailable();
    const w = mediaRecord(m.attempt, [
      "attempt_id",
      "scan_id",
      "object_id",
      "assignment_digest",
      "backend_generation",
      "backend_configuration_digest",
      "created_at",
      "admission_expires_at",
      "capability_expires_at",
      "state",
      "issued_at",
      "retired",
      "write_policy_digest",
      "write_closed",
    ]);
    const c = mediaRecord(m.closure, [
      "attempt_id",
      "outcome",
      "policy_digest",
      "observed_at",
      "claim_digest",
    ]);
    const id = mediaUUID(w.attempt_id);
    if (attempts.has(id)) throw initialMediaUnavailable();
    attempts.add(id);
    mediaDigest(w.write_policy_digest);
    for (
      const key of [
        "created_at",
        "admission_expires_at",
        "capability_expires_at",
        "issued_at",
      ]
    ) cpmClosureTimestamp(w[key]);
    cpmClosureTimestamp(c.observed_at);
    const created = Date.parse(w.created_at as string);
    if (
      w.scan_id !== s.scan_id ||
      w.object_id !== p.role_mapping[index].object_id ||
      w.assignment_digest !== s.assignment_digest ||
      w.backend_generation !== s.backend_generation ||
      w.backend_configuration_digest !== s.backend_configuration_digest ||
      w.state !== "may_have_issued" ||
      w.retired !== false || w.write_closed !== true || c.attempt_id !== id ||
      c.outcome !== "live_object" ||
      c.policy_digest !== w.write_policy_digest || c.claim_digest !== null ||
      w.admission_expires_at !==
        new Date(a.expires_at_ms).toISOString().replace("Z", "000Z") ||
      w.created_at !== new Date(created).toISOString().replace("Z", "000Z") ||
      created < a.created_at_ms ||
      w.capability_expires_at !==
        new Date(Math.min(a.expires_at_ms, created + 600_000))
          .toISOString().replace("Z", "000Z") ||
      (w.created_at as string) > (w.issued_at as string) ||
      (w.issued_at as string) >= (w.capability_expires_at as string) ||
      (c.observed_at as string) < (w.issued_at as string)
    ) throw initialMediaUnavailable();
  }
  if (
    r.snapshot_digest !==
      await digest(
        "merian.initial-analysis.cpm-verification-start.v1",
        r.snapshot_canonical,
      )
  ) throw initialMediaUnavailable();
  return Object.freeze({
    ...identity,
    attempt_id: r.attempt_id as string,
    snapshot_canonical: r.snapshot_canonical,
    snapshot_digest: r.snapshot_digest as string,
  });
}
async function evidence(
  value: unknown,
  start: Readonly<CpmVerificationStart>,
): Promise<Readonly<CpmAdmissionEvidence>> {
  const text = bounded(value),
    s = JSON.parse(start.snapshot_canonical) as Snapshot;
  const v = mediaRecord(JSON.parse(text), [
    "version",
    "protocol",
    "attempt_id",
    "snapshot_digest",
    "profile_digest",
    "verifier_build_digest",
    "objects",
  ]);
  if (
    v.version !== 1 || v.protocol !== "cpm_photo_full_bytes_v1" ||
    v.attempt_id !== start.attempt_id ||
    v.snapshot_digest !== start.snapshot_digest ||
    v.profile_digest !== s.profile_digest ||
    v.verifier_build_digest !== s.verifier_build_digest ||
    !Array.isArray(v.objects) ||
    v.objects.length !== s.members.length
  ) throw initialMediaUnavailable();
  for (const [index, item] of v.objects.entries()) {
    const object = mediaRecord(item, [
      "object_id",
      "photo_ordinal",
      "role",
      "byte_count",
      "sha256",
      "content_type",
      "structural_acceptance",
    ]);
    const m = s.members[index].role, d = m.declaration;
    if (
      object.object_id !== m.object_id ||
      object.photo_ordinal !== m.photo_ordinal || object.role !== m.role ||
      object.byte_count !== d.byte_count || object.sha256 !== d.sha256 ||
      object.content_type !== d.declared_content_type ||
      object.structural_acceptance !== true
    ) throw initialMediaUnavailable();
  }
  // Schema 2 retains the entire already-validated CPM content document exactly.
  // Its inner content version remains 1. Schema 1's decoded description strings
  // cannot represent every accepted UTF-8 value (notably NUL) in PostgreSQL.
  const candidate = JSON.parse(start.candidate_canonical);
  const submission = candidate.content_canonical as string;
  const descriptions = initialCanonicalText(JSON.parse(submission).contexts);
  const submissionDigest = await digest(
    "merian.initial-analysis.cpm-photo-content.v1",
    submission,
  );
  if (
    submissionDigest !== JSON.parse(start.assignment_canonical).content_digest
  ) {
    throw initialMediaUnavailable();
  }
  return Object.freeze({
    ...start,
    input_schema_version: 2 as const,
    binding_version: 4 as const,
    submission_canonical: submission,
    submission_digest: submissionDigest,
    descriptions_canonical: descriptions,
    descriptions_digest: await digest(
      "merian.initial-analysis.cpm-photo-contexts.v1",
      descriptions,
    ),
    verification_canonical: text,
    verification_digest: await digest(
      "merian.initial-analysis.cpm-photo-verification.v1",
      text,
    ),
  });
}

/** Recovery first, one committed start acknowledgement, one complete verifier
 * invocation and one atomic admission attempt. Unknown outcomes reconcile only.
 * No route imports this owner; dependency injection is not installed authority. */
export async function verifyAndAdmitInitialCpmPhoto(
  bridge: CpmPhotoAdmissionBridge,
  value: CpmAdmissionIdentity,
  caller: AbortSignal,
): Promise<typeof held | typeof admitted> {
  const r = mediaRecord(value, [
    "owner_id",
    "scan_id",
    "candidate_canonical",
    "assignment_canonical",
    "assignment_digest",
  ]);
  mediaUUID(r.owner_id);
  mediaUUID(r.scan_id);
  mediaDigest(r.assignment_digest);
  if (
    typeof r.candidate_canonical !== "string" ||
    typeof r.assignment_canonical !== "string"
  ) throw initialMediaUnavailable();
  parseInitialCpmPhotoCandidate(r.candidate_canonical);
  const identity = Object.freeze({ ...r }) as unknown as Readonly<
    CpmAdmissionIdentity
  >;
  const candidate = parseInitialCanonicalText(identity.candidate_canonical);
  const assignment = parseInitialCanonicalText(identity.assignment_canonical);
  return await initialDeadline(caller, 30_000, async (signal) => {
    if (
      await initialAbortable(
          signal,
          () => initialCpmPhotoAssignmentDigest(candidate, assignment),
        ) !==
        identity.assignment_digest ||
      (assignment as { scan_id: string }).scan_id !== identity.scan_id
    ) throw initialMediaUnavailable();
    const recover = () =>
      initialDeadline(signal, 5_000, async (phase) => {
        const found = await initialAbortable(phase, () =>
          bridge.recover(identity, phase));
        if (typeof found !== "boolean") {
          throw initialMediaUnavailable();
        }
        checkInitialDeadline(phase);
        return found;
      });
    try {
      if (await recover()) return admitted;
    } catch {
      return held;
    }
    const expiry = (assignment as { expires_at_ms: number }).expires_at_ms;
    const available =
      Math.min(initialRemainingDeadline(signal), expiry - Date.now()) - 5_000;
    if (available <= 0) return held;
    try {
      await initialDeadline(signal, available, async (work) => {
        const begun = await initialAbortable(
          work,
          () => bridge.begin(identity, work),
        );
        // Decode only the fresh acknowledgement. A stored held state cannot be
        // upgraded to IO authority, including after an uncertain earlier start.
        const started = await initialAbortable(
          work,
          () => decodeStart(begun, identity),
        );
        const verified = await initialAbortable(
          work,
          () => bridge.verify(started, work),
        );
        const frozen = await initialAbortable(
          work,
          () => evidence(verified, started),
        );
        checkInitialDeadline(work);
        await initialAbortable(work, () => bridge.admit(frozen, work));
        checkInitialDeadline(work);
      });
    } catch {
      /* Only exact committed receipt reconciliation is allowed below. */
    }
    try {
      return await recover() ? admitted : held;
    } catch {
      return held;
    }
  });
}
