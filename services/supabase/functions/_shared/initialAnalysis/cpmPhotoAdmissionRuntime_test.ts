import { initialPhotoTransfer } from "../../initial-photo-transfer/handler.ts";
import { fixture as transferFixture } from "../../initial-photo-transfer/fixtures.ts";
import { assertEquals } from "@std/assert";
import { safeJpeg } from "../analysisHistory/testing/publicPhotoFixtures.ts";
import { fixture, hash } from "./cpmPhotoAdmissionTestFixtures.ts";
import { initialCanonicalText } from "./canonical.ts";
import { initialCpmPhotoContentDigest } from "./cpmPhotoContent.ts";
import { initialCpmPhotoCandidateDigest } from "./cpmPhotoCandidate.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import { createCpmPhotoAdmissionRuntime } from "./cpmPhotoAdmissionRuntime.ts";

async function exercise(mode: string) {
  const bytes = safeJpeg();
  const sha = await initialMediaHash(bytes.slice());
  const f = await fixture(async (candidate, assignment) => {
    const content = JSON.parse(candidate.content_canonical);
    for (const role of ["source", "ai", "display"] as const) {
      Object.assign(content.photos[0][role], {
        byte_count: bytes.length,
        sha256: sha,
        declared_content_type: "image/jpeg",
      });
      assignment.preparation.role_mapping.find((m) => m.role === role)!
        .declaration = content.photos[0][role];
    }
    candidate.content_canonical = initialCanonicalText(content);
    assignment.content_digest = await initialCpmPhotoContentDigest(content);
    assignment.candidate_digest = await initialCpmPhotoCandidateDigest(
      candidate,
    );
  });
  const config = {
    generation: f.snapshot.backend_generation,
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-preparation/v2",
    credential_profile: "synthetic_only",
    storage_protocol: "conditional_create_permanent_same_key_marker_v1",
  };
  const backend = {
    ...config,
    configuration_digest: await hash(
      "merian.initial-analysis.media.backend.v1",
      initialCanonicalText(config),
    ),
  };
  f.snapshot.backend_configuration_digest = backend.configuration_digest;
  for (const m of f.snapshot.members) {
    m.attempt.backend_configuration_digest = backend.configuration_digest;
  }
  f.begun.snapshot_canonical = initialCanonicalText(f.snapshot);
  f.begun.snapshot_digest = await hash(
    "merian.initial-analysis.cpm-verification-start.v1",
    f.begun.snapshot_canonical,
  );
  const dimensions = {
    maximumWidth: 16384,
    maximumHeight: 16384,
    maximumPixels: 100_000_000,
  };
  const policy = {
    profile_digest: f.snapshot.profile_digest,
    verifier_build_digest: f.snapshot.verifier_build_digest,
    dimensions: { source: dimensions, ai: dimensions, display: dimensions },
    backend,
  };
  const calls: string[] = [];
  const controller = new AbortController();
  let committed = mode === "recovered",
    begun = false,
    revoked = false,
    signed = 0,
    fetched = 0,
    admits = 0;
  const reply = (v: unknown, status = 200) =>
    Promise.resolve(new Response(JSON.stringify(v), { status }));
  const receipt = () => ({
    version: 1,
    variant: "client_prepared_photo",
    authority: "none",
    outcome: committed ? "admitted" : "unadmitted",
    owner_id: f.identity.owner_id,
    scan_id: f.identity.scan_id,
    candidate_digest: f.snapshot.candidate_digest,
    assignment_digest: f.identity.assignment_digest,
    admission_receipt_id: committed
      ? "00000000-0000-4000-8000-000000000777"
      : null,
    admission_receipt_digest: committed ? "d".repeat(64) : null,
  });
  const runtime = await createCpmPhotoAdmissionRuntime(
    mode === "recovered" || mode === "held" ? [] : [policy],
    "a".repeat(64),
    {
      sign: (_profile, request) => {
        signed++;
        if (mode === "revoke_after_sign") revoked = true;
        return Promise.resolve(request);
      },
      fetch: () => {
        fetched++;
        if (mode === "cancel_before_response") controller.abort();
        if (mode === "revoke_after_read") revoked = true;
        return Promise.resolve(
          new Response(
            mode === "cancel_during_stream"
              ? new ReadableStream({
                start(stream) {
                  stream.enqueue(bytes.slice(0, Math.floor(bytes.length / 2)));
                },
                pull(stream) {
                  controller.abort();
                  stream.close();
                },
              })
              : bytes.slice(),
            {
              headers: {
                "content-length": String(bytes.length),
                "content-type": "image/jpeg",
                "cache-control": "private, no-store",
              },
            },
          ),
        );
      },
    },
    (url, init) => {
      const operation = new URL(String(url)).pathname.split("/").at(-1)!;
      calls.push(operation);
      assertEquals(new URL(String(url)).origin, "https://trusted.invalid");
      const body = JSON.parse(String(init?.body));
      if (operation === "read_initial_cpm_photo_admission") {
        return reply(
          receipt(),
        );
      }
      if (operation === "begin_initial_cpm_photo_admission") {
        begun = true;
        return reply(
          mode === "held"
            ? { version: 1, outcome: "held", authority: "none" }
            : f.begun,
        );
      }
      assertEquals(begun, true);
      if (operation === "assert_initial_cpm_photo_verification_current") {
        assertEquals(body.p_attempt, f.begun.attempt_id);
        assertEquals(body.p_snapshot_digest, f.begun.snapshot_digest);
        if (revoked || mode === "revoke_before_read") return reply({}, 409);
        return reply({
          version: 1,
          outcome: "current",
          authority: "none",
          owner_id: f.identity.owner_id,
          scan_id: f.identity.scan_id,
          assignment_digest: f.identity.assignment_digest,
          attempt_id: f.begun.attempt_id,
          snapshot_digest: f.begun.snapshot_digest,
        });
      }
      if (operation === "read_initial_cpm_photo_observation") {
        const m = f.snapshot.members.find((m) =>
          m.attempt.attempt_id === body.p_attempt
        )!;
        const observed = {
          binding: {
            attempt_id: m.attempt.attempt_id,
            scan_id: f.identity.scan_id,
            object_id: m.role.object_id,
            assignment_digest: f.identity.assignment_digest,
            backend_generation: backend.generation,
            backend_configuration_digest: backend.configuration_digest,
            issued_at_ms: Date.parse(m.attempt.issued_at),
            verification_policy_digest: m.attempt.write_policy_digest,
          },
          target: {
            outcome: "live_object",
            role: m.role.role,
            byte_count: bytes.length,
            sha256: sha,
            content_type: "image/jpeg",
          },
          backend,
          admission_expires_at_ms: f.snapshot.original_expires_at_ms,
          erasure_claim: null,
        };
        if (mode === "wrong_object") {
          observed.binding.object_id = "00000000-0000-4000-8000-000000000888";
        }
        if (body.p_expected !== null) assertEquals(body.p_expected, observed);
        return reply(observed);
      }
      assertEquals(operation, "admit_initial_cpm_photo");
      assertEquals(fetched, 3);
      assertEquals(revoked, false);
      const verification = JSON.parse(body.p_verification);
      assertEquals(verification.snapshot_digest, f.begun.snapshot_digest);
      assertEquals(
        verification.objects.map((
          o: { structural_acceptance: boolean; sha256: string },
        ) => [o.structural_acceptance, o.sha256]),
        [[true, sha], [true, sha], [true, sha]],
      );
      admits++;
      committed = true;
      if (mode === "lost_ack" || mode === "facade_lost_ack") {
        return Promise.reject(
          new Error("synthetic lost acknowledgement"),
        );
      }
      return reply(receipt());
    },
  );
  if (mode === "facade_lost_ack") {
    const transfer = await transferFixture();
    const assignment = JSON.parse(f.identity.assignment_canonical);
    const request = {
      version: 3,
      action: "verify_cohort",
      scan_id: f.identity.scan_id,
      candidate_canonical: f.identity.candidate_canonical,
      assignment_digest: f.identity.assignment_digest,
      backend_generation: backend.generation,
      backend_configuration_digest: backend.configuration_digest,
      allocation_created_at_ms: assignment.created_at_ms,
      allocation_expires_at_ms: assignment.expires_at_ms,
    };
    const bound = {
      ...transfer.deps,
      admission: runtime,
      recover(
        owner: string,
        candidate: {
          action: string;
          candidateCanonical: string;
          savedAssignmentDigest: string | null;
        },
      ) {
        assertEquals(owner, f.identity.owner_id);
        assertEquals(candidate.action, "status");
        assertEquals(
          candidate.candidateCanonical,
          f.identity.candidate_canonical,
        );
        assertEquals(
          candidate.savedAssignmentDigest,
          f.identity.assignment_digest,
        );
        return Promise.resolve({
          version: 3,
          variant: "client_prepared_photo",
          authority: "none",
          outcome: "allocated",
          assignment_canonical: f.identity.assignment_canonical,
          assignment_digest: f.identity.assignment_digest,
          backend_generation: backend.generation,
          backend_configuration_digest: backend.configuration_digest,
        });
      },
    };
    const send = (body: unknown) =>
      initialPhotoTransfer(
        new Request("https://synthetic.invalid/initial-photo-transfer"),
        body,
        f.identity.owner_id,
        () => bound,
      );
    assertEquals(
      (await send({ ...request, backend_configuration_digest: "a".repeat(64) }))
        .status,
      503,
    );
    assertEquals(
      (await send({ ...request, owner_id: f.identity.owner_id })).status,
      400,
    );
    assertEquals([signed, fetched, admits], [0, 0, 0]);
    for (let index = 0; index < 2; index++) {
      const reply = await send(request);
      assertEquals(reply.status, 200);
      assertEquals(await reply.json(), {
        version: 3,
        outcome: "admitted",
        authority: "none",
        scan_id: f.identity.scan_id,
        candidate_digest: f.snapshot.candidate_digest,
        assignment_digest: f.identity.assignment_digest,
        backend_generation: backend.generation,
        backend_configuration_digest: backend.configuration_digest,
      });
      assertEquals([fetched, admits], [3, 1]);
    }
    assertEquals(transfer.calls, []);
    return;
  }
  const result = await runtime.admit(f.identity, controller.signal);
  if (["success", "lost_ack", "recovered"].includes(mode)) {
    assertEquals(result, {
      version: 1,
      outcome: "admitted",
      authority: "none",
    });
    assertEquals(admits, mode === "recovered" ? 0 : 1);
    assertEquals(fetched, mode === "recovered" ? 0 : 3);
    assertEquals(
      await runtime.admit(f.identity, new AbortController().signal),
      result,
    );
    assertEquals(admits, mode === "recovered" ? 0 : 1);
  } else {
    assertEquals(result.outcome, "held");
    assertEquals(admits, 0);
    if (
      ["held", "wrong_object", "revoke_before_read", "revoke_after_sign"]
        .includes(mode)
    ) assertEquals(fetched, 0);
    if (["held", "wrong_object", "revoke_before_read"].includes(mode)) {
      assertEquals(signed, 0);
    }
  }
  if (mode === "recovered") {
    assertEquals(calls, [
      "read_initial_cpm_photo_admission",
      "read_initial_cpm_photo_admission",
    ]);
  }
}

Deno.test("CPM runtime joins actual JPEG verification and both database adapters without restarting uncertain work", async (t) => {
  const names = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"];
  const saved = names.map((name) => Deno.env.get(name));
  try {
    Deno.env.set(names[0], "https://trusted.invalid");
    Deno.env.set(names[1], "sb_secret_" + "x".repeat(40));
    for (
      const mode of [
        "facade_lost_ack",
        "success",
        "lost_ack",
        "recovered",
        "held",
        "wrong_object",
        "revoke_before_read",
        "revoke_after_sign",
        "revoke_after_read",
        "cancel_before_response",
        "cancel_during_stream",
      ]
    ) {
      await t.step(mode, () => exercise(mode));
    }
  } finally {
    names.forEach((name, i) =>
      saved[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, saved[i]!)
    );
  }
});
