/** Synthetic local fixture only; never a profile installation. */
import originalCandidate from "../_shared/initialAnalysis/fixtures/cpm-photo-candidate-v1.json" with {
  type: "json",
};
import assignmentFixture from "../_shared/initialAnalysis/fixtures/cpm-photo-assignment-v1.json" with {
  type: "json",
};
import { initialCanonicalText } from "../_shared/initialAnalysis/canonical.ts";
import { initialCpmPhotoCandidateDigest } from "../_shared/initialAnalysis/cpmPhotoCandidate.ts";
import { initialCpmPhotoContentDigest } from "../_shared/initialAnalysis/cpmPhotoContent.ts";
import { initialCpmPhotoAssignmentDigest } from "../_shared/initialAnalysis/cpmPhotoAssignment.ts";
import { initialMediaHash } from "../_shared/initialAnalysis/mediaBinding.ts";
import { transferPolicyCatalog } from "./catalog.ts";
import type { TransferDependencies } from "./handler.ts";
import { assertEquals } from "@std/assert";

export const owner = "00000000-0000-4000-8000-000000000009";
export const attempt = "00000000-0000-4000-8000-000000000300";
export async function fixture(
  roleIndex = 0,
  submittedBytes?: Uint8Array<ArrayBuffer>,
) {
  const candidate = structuredClone(originalCandidate);
  const assignment = structuredClone(assignmentFixture.assignment);
  const now = Date.now();
  assignment.created_at_ms = now - 10_000;
  assignment.expires_at_ms = now + 1_790_000;
  const selected = assignment.preparation.role_mapping[roleIndex];
  if (submittedBytes) {
    const content = JSON.parse(candidate.candidate.content_canonical);
    const declaration = content.photos[selected.photo_ordinal][selected.role];
    declaration.byte_count = submittedBytes.length;
    declaration.sha256 = await initialMediaHash(submittedBytes);
    Object.assign(selected.declaration, declaration);
    candidate.candidate.content_canonical = initialCanonicalText(content);
    assignment.content_digest = await initialCpmPhotoContentDigest(content);
    assignment.candidate_digest = await initialCpmPhotoCandidateDigest(
      candidate.candidate,
    );
  }
  const backend = {
    generation: assignment.preparation.backend_generation,
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-preparation/v2",
    credential_profile: "synthetic_only",
    storage_protocol: "conditional_create_permanent_same_key_marker_v1",
  };
  const backendDigest = await initialMediaHash(
    new TextEncoder().encode(
      `merian.initial-analysis.media.backend.v1\n${
        initialCanonicalText(backend)
      }`,
    ),
  );
  const digest = await initialCpmPhotoAssignmentDigest(
    candidate.candidate,
    assignment,
  );
  const recovered = {
    version: 3,
    variant: "client_prepared_photo",
    outcome: "allocated",
    authority: "none",
    assignment_canonical: initialCanonicalText(assignment),
    assignment_digest: digest,
    backend_generation: backend.generation,
    backend_configuration_digest: backendDigest,
  };
  const request = {
    version: 1,
    action: "issue",
    scan_id: assignment.scan_id,
    assignment_digest: digest,
    object_id: selected.object_id,
    allocation_created_at_ms: assignment.created_at_ms,
    allocation_expires_at_ms: assignment.expires_at_ms,
    candidate_canonical: initialCanonicalText(candidate.candidate),
  };
  const entry = {
    policy_digest: "b".repeat(64),
    profile: {
      credential_profile: "synthetic_only",
      backend_generation: backend.generation,
      backend_configuration_digest: backendDigest,
      access_key_id: "SYNTHETIC_KEY_NOT_REAL",
      secret_access_key: "SYNTHETIC_SECRET_NOT_REAL",
    },
  };
  const created = now - 1000,
    expiry = Math.min(created + 600_000, assignment.expires_at_ms);
  const fresh = {
    outcome: "fresh",
    attempt_id: attempt,
    created_at_ms: created,
    capability_expires_at_ms: expiry,
    observation: {
      binding: {
        attempt_id: attempt,
        scan_id: request.scan_id,
        object_id: request.object_id,
        assignment_digest: digest,
        backend_generation: backend.generation,
        backend_configuration_digest: backendDigest,
        issued_at_ms: now - 500,
        verification_policy_digest: entry.policy_digest,
      },
      target: {
        outcome: "live_object",
        role: selected.role,
        byte_count: selected.declaration.byte_count,
        content_type: selected.declaration.declared_content_type,
        sha256: selected.declaration.sha256,
      },
      backend: { ...backend, configuration_digest: backendDigest },
      admission_expires_at_ms: assignment.expires_at_ms,
      erasure_claim: null,
    },
  };
  const calls: string[] = [];
  let began = false;
  const deps: TransferDependencies = {
    catalog: transferPolicyCatalog([entry]),
    recover: (user, value) => {
      calls.push("recover");
      assertEquals(user, owner);
      assertEquals(value.version, 3);
      assertEquals(value.action, "status");
      assertEquals(value.savedAssignmentDigest, digest);
      return Promise.resolve(recovered);
    },
    bridge: {
      begin: (identity) => {
        calls.push("begin");
        assertEquals(identity, {
          owner,
          scan: request.scan_id,
          assignment_digest: digest,
          object: request.object_id,
          policy: entry.policy_digest,
        });
        const value = began ? { outcome: "held", attempt_id: attempt } : fresh;
        began = true;
        return Promise.resolve(value);
      },
      requireCurrent: (input) => {
        calls.push("current");
        assertEquals<unknown>(input, fresh.observation);
        return Promise.resolve();
      },
      readStatus: (identity, saved) => {
        calls.push("status");
        assertEquals(identity.owner, owner);
        assertEquals(saved, null);
        return Promise.resolve({
          version: 1,
          authority: "none",
          scan_id: request.scan_id,
          assignment_digest: digest,
          object_id: request.object_id,
          attempt: began
            ? {
              attempt_id: attempt,
              state: "may_have_issued",
              created_at_ms: created,
              capability_expires_at_ms: expiry,
              write_closed: false,
            }
            : null,
        });
      },
    },
  };
  const { candidate_canonical: _candidate, ...status } = request;
  return {
    request,
    status: { ...status, action: "status" },
    recovered,
    entry,
    fresh,
    deps,
    calls,
    backendDigest,
  };
}
