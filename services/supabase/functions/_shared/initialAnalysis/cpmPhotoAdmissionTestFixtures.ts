import { assertEquals } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialCpmPhotoAssignmentDigest } from "./cpmPhotoAssignment.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import {
  type CpmPhotoAdmissionBridge,
  verifyAndAdmitInitialCpmPhoto,
} from "./cpmPhotoAdmission.ts";
import candidateFixture from "./fixtures/cpm-photo-candidate-v1.json" with {
  type: "json",
};
import assignmentFixture from "./fixtures/cpm-photo-assignment-v1.json" with {
  type: "json",
};

export const hash = (domain: string, text: string) =>
  initialMediaHash(new TextEncoder().encode(`${domain}\n${text}`));
export const timestamp = (n: number) =>
  new Date(n).toISOString().replace("Z", "000Z");
export async function fixture(
  prepare?: (
    candidate: typeof candidateFixture.candidate,
    assignment: typeof assignmentFixture.assignment,
  ) => Promise<void>,
) {
  const candidate = structuredClone(candidateFixture.candidate);
  const a = structuredClone(assignmentFixture.assignment);
  await prepare?.(candidate, a);
  a.created_at_ms = Date.now() - 1000;
  a.expires_at_ms = a.created_at_ms + 1_800_000;
  const identity = {
    owner_id: "00000000-0000-4000-8000-000000000901",
    scan_id: a.scan_id,
    candidate_canonical: initialCanonicalText(candidate),
    assignment_canonical: initialCanonicalText(a),
    assignment_digest: await initialCpmPhotoAssignmentDigest(candidate, a),
  };
  const snapshot = {
    version: 1,
    owner_id: identity.owner_id,
    scan_id: a.scan_id,
    candidate_digest: a.candidate_digest,
    content_digest: a.content_digest,
    assignment_digest: identity.assignment_digest,
    profile_digest: a.preparation.profile_digest,
    verifier_build_digest: a.preparation.verifier_build_digest,
    backend_generation: a.preparation.backend_generation,
    backend_configuration_digest: "f".repeat(64),
    original_expires_at_ms: a.expires_at_ms,
    members: a.preparation.role_mapping.map((role, index) => {
      const attempt_id = `00000000-0000-4000-8000-00000000080${index}`;
      return {
        role,
        attempt: {
          attempt_id,
          scan_id: a.scan_id,
          object_id: role.object_id,
          assignment_digest: identity.assignment_digest,
          backend_generation: a.preparation.backend_generation,
          backend_configuration_digest: "f".repeat(64),
          created_at: timestamp(a.created_at_ms),
          admission_expires_at: timestamp(a.expires_at_ms),
          capability_expires_at: timestamp(a.created_at_ms + 600_000),
          issued_at: timestamp(a.created_at_ms + 10),
          state: "may_have_issued",
          retired: false,
          write_policy_digest: "a".repeat(64),
          write_closed: true,
        },
        closure: {
          attempt_id,
          outcome: "live_object",
          policy_digest: "a".repeat(64),
          observed_at: timestamp(a.created_at_ms + 20),
          claim_digest: null,
        },
      };
    }),
  };
  const begun = {
    version: 1,
    outcome: "started",
    attempt_id: "00000000-0000-4000-8000-000000000999",
    snapshot_canonical: initialCanonicalText(snapshot),
    snapshot_digest: await hash(
      "merian.initial-analysis.cpm-verification-start.v1",
      initialCanonicalText(snapshot),
    ),
  };
  const verified = {
    version: 1,
    protocol: "cpm_photo_full_bytes_v1",
    attempt_id: begun.attempt_id,
    snapshot_digest: begun.snapshot_digest,
    profile_digest: snapshot.profile_digest,
    verifier_build_digest: snapshot.verifier_build_digest,
    objects: snapshot.members.map(({ role: m }) => ({
      object_id: m.object_id,
      photo_ordinal: m.photo_ordinal,
      role: m.role,
      byte_count: m.declaration.byte_count,
      sha256: m.declaration.sha256,
      content_type: m.declaration.declared_content_type,
      structural_acceptance: true,
    })),
  };
  const calls: string[] = [];
  let committed = false;
  const bridge: CpmPhotoAdmissionBridge = {
    recover: () => {
      calls.push("recover");
      return Promise.resolve(committed);
    },
    begin: () => {
      calls.push("begin");
      return Promise.resolve(begun);
    },
    verify: () => {
      calls.push("verify");
      return Promise.resolve(verified);
    },
    admit: async (evidence) => {
      calls.push("admit");
      assertEquals(evidence.candidate_canonical, identity.candidate_canonical);
      assertEquals(
        evidence.assignment_canonical,
        identity.assignment_canonical,
      );
      assertEquals(
        evidence.verification_canonical,
        initialCanonicalText(verified),
      );
      assertEquals(
        evidence.verification_digest,
        await hash(
          "merian.initial-analysis.cpm-photo-verification.v1",
          evidence.verification_canonical,
        ),
      );
      committed = true;
    },
  };
  return {
    identity,
    snapshot,
    begun,
    verified,
    bridge,
    calls,
    commit() {
      committed = true;
    },
    run(signal = new AbortController().signal) {
      return verifyAndAdmitInitialCpmPhoto(bridge, identity, signal);
    },
  };
}
