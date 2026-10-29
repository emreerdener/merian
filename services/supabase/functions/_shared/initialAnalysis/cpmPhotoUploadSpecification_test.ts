import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import { prepareCpmPhotoUploadSpecification } from "./cpmPhotoUploadSpecification.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

async function fixture() {
  const config = {
    generation: id(4),
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-preparation/v2",
    credential_profile: "synthetic_only",
    storage_protocol: "conditional_create_permanent_same_key_marker_v1",
  };
  const digest = await initialMediaHash(new TextEncoder().encode(
    `merian.initial-analysis.media.backend.v1\n${initialCanonicalText(config)}`,
  ));
  return {
    input: {
      binding: {
        attempt_id: id(1),
        scan_id: id(2),
        object_id: id(3),
        assignment_digest: "a".repeat(64),
        backend_generation: id(4),
        backend_configuration_digest: digest,
      },
      target: {
        outcome: "live_object",
        role: "source",
        byte_count: 4,
        content_type: "image/jpeg",
        sha256: "b".repeat(64),
      },
      backend: { ...config, configuration_digest: digest },
      created_at_ms: 1000,
      admission_expires_at_ms: 1_801_000,
      capability_expires_at_ms: 601_000,
    },
    profiles: [{
      credential_profile: "synthetic_only",
      backend_generation: id(4),
      backend_configuration_digest: digest,
    }],
  };
}

for (
  const [role, limit] of [
    ["source", 33_554_432],
    ["ai", 5_242_880],
    ["display", 4_194_304],
  ] as const
) {
  Deno.test(`CPM ${role} specification fixes exact conditional creation requirements`, async () => {
    const f = await fixture();
    f.input.target.role = role;
    f.input.target.byte_count = limit;
    const result = await prepareCpmPhotoUploadSpecification(
      f.input,
      f.profiles,
    );
    assertEquals(result.kind, "unqualified_cpm_upload_specification");
    assertEquals(result.method, "PUT");
    assertEquals(result.destination, {
      direct_endpoint: f.input.backend.direct_endpoint,
      private_bucket: "synthetic-private",
      key: `initial-preparation/v2/${id(2)}/${id(3)}`,
    });
    assertEquals(result.headers, {
      "If-None-Match": "*",
      "Content-Type": "image/jpeg",
      "Content-Length": String(limit),
      "Cache-Control": "private, no-store",
    });
    assertEquals(result.payload_integrity, {
      required_algorithm: "sha256",
      required_digest: "b".repeat(64),
      provider_enforcement: "unqualified",
    });
    assertEquals(result.capability_expires_at_ms, 601_000);
    f.input.target.byte_count = limit + 1;
    await assertRejects(() =>
      prepareCpmPhotoUploadSpecification(f.input, f.profiles)
    );
  });
}

Deno.test("CPM specification rejects operation, header, metadata and key substitution", async (t) => {
  const f = await fixture();
  for (
    const extra of [
      { method: "COPY" },
      { method: "DELETE" },
      { method: "POST" },
      { query: "uploads" },
      { query: "uploadId=synthetic" },
      { headers: { "If-None-Match": "other" } },
      { metadata: { "merian-state": "erased-v1" } },
      { key: "initial-preparation/v2/other" },
      { body: new Uint8Array(4) },
      { state: "may_have_issued" },
    ]
  ) {
    await t.step(JSON.stringify(extra), async () => {
      await assertRejects(() =>
        prepareCpmPhotoUploadSpecification({ ...f.input, ...extra }, f.profiles)
      );
    });
  }
  await assertRejects(() =>
    prepareCpmPhotoUploadSpecification({
      ...f.input,
      target: { outcome: "retired_marker" },
    }, f.profiles)
  );
  await assertRejects(() =>
    prepareCpmPhotoUploadSpecification({
      ...f.input,
      binding: { ...f.input.binding, object_id: "../other" },
    }, f.profiles)
  );
});

Deno.test("CPM specification rejects altered backend and unknown or mismatched profile", async (t) => {
  const f = await fixture();
  for (
    const [key, value] of Object.entries({
      generation: id(5),
      configuration_digest: "c".repeat(64),
      provider: "s3",
      direct_endpoint: f.input.backend.direct_endpoint + "/extra",
      private_bucket: "different-private",
      namespace: "initial-analysis/v1",
      credential_profile: "unknown",
      storage_protocol: "different_protocol",
    })
  ) {
    await t.step(key, async () => {
      await assertRejects(() =>
        prepareCpmPhotoUploadSpecification({
          ...f.input,
          backend: { ...f.input.backend, [key]: value },
        }, f.profiles)
      );
    });
  }
  for (
    const profiles of [
      [],
      [f.profiles[0], f.profiles[0]],
      Array.from({ length: 17 }, () => f.profiles[0]),
      [{ ...f.profiles[0], credential_profile: "different" }],
      [{ ...f.profiles[0], backend_generation: id(5) }],
      [{ ...f.profiles[0], backend_configuration_digest: "c".repeat(64) }],
      [{ ...f.profiles[0], secret: "synthetic-disallowed-field" }],
    ]
  ) {
    await assertRejects(() =>
      prepareCpmPhotoUploadSpecification(f.input, profiles)
    );
  }
});

Deno.test("CPM specification preserves original shortened expiry and rejects clock extension", async () => {
  const f = await fixture();
  f.input.admission_expires_at_ms = 3000;
  f.input.capability_expires_at_ms = 3000;
  const result = await prepareCpmPhotoUploadSpecification(f.input, f.profiles);
  assertEquals(result.capability_expires_at_ms, 3000);
  for (
    const clocks of [
      { capability_expires_at_ms: 3001 },
      { capability_expires_at_ms: 2999 },
      { admission_expires_at_ms: 1000, capability_expires_at_ms: 1000 },
      { created_at_ms: 1000.5 },
      { admission_expires_at_ms: Infinity },
    ]
  ) {
    await assertRejects(() =>
      prepareCpmPhotoUploadSpecification({ ...f.input, ...clocks }, f.profiles)
    );
  }
});

Deno.test("CPM specification snapshots every mutable caller fact before suspension", async () => {
  const f = await fixture();
  const pending = prepareCpmPhotoUploadSpecification(f.input, f.profiles);
  f.input.binding.object_id = id(9);
  f.input.target.sha256 = "c".repeat(64);
  f.input.target.byte_count = 100;
  f.input.backend.private_bucket = "changed-after-call";
  f.profiles[0].backend_generation = id(9);
  f.profiles.splice(0);
  f.input.capability_expires_at_ms = 9_999_999;
  const result = await pending;
  assertEquals(result.binding.object_id, id(3));
  assertEquals(result.target.sha256, "b".repeat(64));
  assertEquals(result.headers["Content-Length"], "4");
  assertEquals(result.destination.private_bucket, "synthetic-private");
  assertEquals(result.profile.backend_generation, id(4));
  assertEquals(result.capability_expires_at_ms, 601_000);
  for (
    const item of [
      result,
      result.binding,
      result.target,
      result.profile,
      result.destination,
      result.headers,
      result.payload_integrity,
    ]
  ) {
    assertEquals(Object.isFrozen(item), true);
  }
  assertThrows(() =>
    Object.assign(result.headers, { "If-None-Match": "different" })
  );
});
