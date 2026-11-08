import { assertEquals, assertRejects } from "@std/assert";
import {
  safeJpeg,
  safePng,
} from "../analysisHistory/testing/publicPhotoFixtures.ts";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import {
  type CpmRetentionDependencies,
  verifyInitialCpmRetention,
} from "./cpmPhotoRetention.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const digest = (c: string) => c.repeat(64);
const hash = (domain: string, value: unknown) =>
  initialMediaHash(
    new TextEncoder().encode(domain + "\n" + initialCanonicalText(value)),
  );

async function fixture(count = 1, png = false) {
  const jpeg = safeJpeg(), source = png ? safePng() : jpeg;
  const config = {
    generation: id(50),
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
      config,
    ),
  };
  const policy = {
    write_policy_digest: digest("1"),
    retention_build_digest: digest("2"),
    qualification_evidence_digest: digest("3"),
    reviewed_revision: "4".repeat(40),
    protocol: "cpm_in_place_adoption_v1",
    verification_max_duration_ms: 150000,
    verification_max_age_ms: 30000,
    clock_skew_ms: 1000,
  };
  const objects: {
    photo_ordinal: number;
    role: string;
    reference_id: string;
    object_id: string;
    backend_generation: string;
    backend_configuration_digest: string;
    namespace: string;
    byte_count: number;
    sha256: string;
    content_type: string;
  }[] = [];
  for (let n = 0; n < count; n++) {
    for (const [index, role] of ["source", "ai", "display"].entries()) {
      const bytes = role === "source" ? source : jpeg;
      objects.push({
        photo_ordinal: n,
        role,
        reference_id: id(100 + n * 3 + index),
        object_id: id(200 + n * 3 + index),
        backend_generation: backend.generation,
        backend_configuration_digest: backend.configuration_digest,
        namespace: "initial-preparation/v2",
        byte_count: bytes.length,
        sha256: await initialMediaHash(bytes.slice()),
        content_type: png && role === "source" ? "image/png" : "image/jpeg",
      });
    }
  }
  const binding = {
    version: 1,
    variant: "cpm_in_place_adoption_v1",
    owner_id: id(1),
    scan_id: id(2),
    admission_receipt_id: id(3),
    admission_receipt_digest: digest("5"),
    cpm_verification_digest: digest("6"),
    retained_roles_digest: digest("7"),
    result_evidence_id: id(4),
    result_digest: digest("8"),
    retention_policy_digest: await hash(
      "merian.initial-analysis.cpm-retention-policy.v1",
      { version: 1, ...policy },
    ),
    retention_build_digest: policy.retention_build_digest,
    objects,
  };
  const snapshot = {
    binding,
    reads: objects.map((o, index) => ({
      attempt_id: id(300 + index),
      scan_id: binding.scan_id,
      object_id: o.object_id,
      assignment_digest: digest("9"),
      backend_generation: backend.generation,
      backend_configuration_digest: backend.configuration_digest,
      issued_at_ms: 1000,
      verification_policy_digest: policy.write_policy_digest,
    })),
    profile_digest: digest("a"),
    verifier_build_digest: digest("b"),
    policy,
  };
  const dimensions = {
    maximumWidth: 16384,
    maximumHeight: 16384,
    maximumPixels: 100000000,
  };
  const requests: string[] = [];
  let checks = 0;
  const deps: CpmRetentionDependencies = {
    load: () =>
      Promise.resolve({
        retention_policy_digest: binding.retention_policy_digest,
        retention_build_digest: policy.retention_build_digest,
        photo: {
          profile_digest: snapshot.profile_digest,
          verifier_build_digest: snapshot.verifier_build_digest,
          dimensions: {
            source: dimensions,
            ai: dimensions,
            display: dimensions,
          },
          backend,
        },
      }),
    requireCurrent: () => {
      checks++;
      return Promise.resolve();
    },
    storage: {
      sign: (_profile, request) => Promise.resolve(request),
      fetch: (request) => {
        const index = requests.length, object = objects[index];
        const body = object.role === "source" ? source : jpeg;
        requests.push((request as Request).url);
        return Promise.resolve(
          new Response(body.slice(), {
            headers: {
              "content-length": String(body.length),
              "content-type": object.content_type,
              "cache-control": "private, no-store",
            },
          }),
        );
      },
    },
  };
  const controller = new AbortController();
  return {
    snapshot,
    deps,
    requests,
    controller,
    checks: () => checks,
    run: () => verifyInitialCpmRetention(deps, snapshot, controller.signal),
  };
}

Deno.test("terminal verifier reopens all original roles once and returns only interval-bound proof", async () => {
  for (const count of [1, 2]) {
    for (const png of [false, true]) {
      const f = await fixture(count, png), before = Date.now();
      const proof = await f.run();
      const { verification_started_at_ms, verified_at_ms, ...binding } = proof;
      assertEquals(binding, f.snapshot.binding);
      assertEquals(verification_started_at_ms >= before, true);
      assertEquals(verified_at_ms >= verification_started_at_ms, true);
      assertEquals(f.requests.length, 3 * count);
      assertEquals(new Set(f.requests).size, 3 * count);
      assertEquals(f.checks() > 3 * count * 3, true);
      assertEquals(Object.isFrozen(proof.objects[0]), true);
    }
  }
});

Deno.test("terminal verifier rejects missing, duplicate, swapped and redirected original roles before IO", async () => {
  for (
    const change of [
      (s: Awaited<ReturnType<typeof fixture>>["snapshot"]) =>
        s.binding.objects.pop(),
      (s: Awaited<ReturnType<typeof fixture>>["snapshot"]) =>
        s.binding.objects.reverse(),
      (s: Awaited<ReturnType<typeof fixture>>["snapshot"]) =>
        s.binding.objects[1].reference_id = s.binding.objects[0].reference_id,
      (s: Awaited<ReturnType<typeof fixture>>["snapshot"]) =>
        s.reads[0].object_id = id(999),
      (s: Awaited<ReturnType<typeof fixture>>["snapshot"]) =>
        s.binding.objects[0].namespace = "other",
      (s: Awaited<ReturnType<typeof fixture>>["snapshot"]) =>
        s.policy.retention_build_digest = s.verifier_build_digest,
    ]
  ) {
    const f = await fixture();
    change(f.snapshot);
    await assertRejects(f.run);
    assertEquals(f.requests.length, 0);
  }
});

Deno.test("terminal verifier requires exact qualified policy/build and current authorization", async () => {
  for (const mode of ["missing", "build", "current", "digest"]) {
    const f = await fixture(), load = f.deps.load;
    if (mode === "missing") {
      f.deps.load = () => Promise.reject(new Error("unavailable"));
    }
    if (mode === "build") {
      f.deps.load = async (...args) => ({
        ...await load(...args),
        retention_build_digest: digest("d"),
      });
    }
    if (mode === "current") {
      f.deps.requireCurrent = () => Promise.reject(new Error("retired"));
    }
    if (mode === "digest") f.snapshot.policy.clock_skew_ms = 999;
    await assertRejects(f.run);
    assertEquals(f.requests.length, 0);
  }
});

Deno.test("terminal verifier refuses wrong bytes and post-read retirement without retry", async () => {
  const broken = await fixture();
  broken.deps.storage.fetch = () => {
    broken.requests.push("synthetic");
    return Promise.resolve(
      new Response(
        new Uint8Array(broken.snapshot.binding.objects[0].byte_count),
        {
          headers: {
            "content-length": String(
              broken.snapshot.binding.objects[0].byte_count,
            ),
            "content-type": "image/jpeg",
            "cache-control": "private, no-store",
          },
        },
      ),
    );
  };
  await assertRejects(broken.run);
  assertEquals(broken.requests.length, 1);
  const retired = await fixture();
  retired.deps.requireCurrent = () =>
    retired.requests.length === 3
      ? Promise.reject(new Error("retired"))
      : Promise.resolve();
  await assertRejects(retired.run);
  assertEquals(retired.requests.length, 3);
});

Deno.test("terminal verifier snapshots caller data and rejects wall-clock rollback or stale full interval", async () => {
  const f = await fixture(), load = f.deps.load;
  f.deps.load = async (...args) => {
    f.snapshot.binding.result_digest = digest("d");
    return await load(...args);
  };
  const result = await f.run();
  assertEquals(result.result_digest, digest("8"));
  for (const delta of [-1, 150001]) {
    const f = await fixture(), original = Date.now, base = original();
    let calls = 0;
    Date.now = () => calls++ === 0 ? base : base + delta;
    try {
      await assertRejects(f.run);
    } finally {
      Date.now = original;
    }
  }
});

Deno.test("terminal verifier honors caller cancellation before any media request", async () => {
  const f = await fixture();
  f.controller.abort();
  await assertRejects(f.run);
  assertEquals(f.requests.length, 0);
});

Deno.test("terminal verifier cancels and unlocks an interrupted streamed read without proof or retry", async () => {
  for (const mode of ["caller", "deadline"]) {
    const f = await fixture();
    if (mode === "deadline") {
      f.snapshot.policy.verification_max_duration_ms = 50;
      f.snapshot.binding.retention_policy_digest = await hash(
        "merian.initial-analysis.cpm-retention-policy.v1",
        { version: 1, ...f.snapshot.policy },
      );
    }
    let cancelled = false, requests = 0;
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(safeJpeg().subarray(0, 8));
      },
      pull() {
        if (mode === "caller") f.controller.abort();
        return new Promise<void>(() => {});
      },
      cancel() {
        cancelled = true;
      },
    });
    f.deps.storage.fetch = () => {
      requests++;
      return Promise.resolve(
        new Response(stream, {
          headers: {
            "content-length": String(f.snapshot.binding.objects[0].byte_count),
            "content-type": "image/jpeg",
            "cache-control": "private, no-store",
          },
        }),
      );
    };
    await assertRejects(f.run);
    assertEquals(requests, 1);
    assertEquals(cancelled, true);
    assertEquals(stream.locked, false);
  }
});
