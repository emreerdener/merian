import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaContractDigest } from "./mediaPreparationProfile.ts";
import {
  assertInitialHandoffCatalogEnvelope,
  initialHandoffCatalogDigest,
  validateInitialHandoffCatalogShape,
  validateInitialHandoffInstallation,
} from "./handoffCatalog.ts";
import vectors from "./fixtures/handoff-catalog-v1.json" with { type: "json" };
Deno.test("handoff catalog declarations bind exact independently encoded identities", async () => {
  assertEquals(
    validateInitialHandoffCatalogShape(
      "destination_backend",
      vectors.destination_backend,
    ),
    vectors.destination_canonical,
  );
  assertEquals(
    await initialHandoffCatalogDigest(
      "destination_backend",
      vectors.destination_canonical,
    ),
    vectors.destination_digest,
  );
  for (const v of vectors.valid) {
    assertEquals(
      await validateInitialHandoffInstallation(
        v.installation,
        v.handoff,
        vectors.protocol_artifact,
        v.preparation,
        vectors.destination_backend,
      ),
      v.installation_canonical,
    );
    assertEquals(
      await initialHandoffCatalogDigest(
        "installation",
        v.installation_canonical,
      ),
      v.installation_digest,
    );
  }
});
Deno.test("installation rejects cross-profile backend adapter and qualification identity drift", async () => {
  const v = vectors.valid[0];
  for (
    const key of [
      "profile_digest",
      "protocol_artifact_digest",
      "copy_adapter_digest",
      "verification_adapter_digest",
      "preparation_profile_digest",
    ]
  ) {
    await assertRejects(
      () =>
        validateInitialHandoffInstallation(
          { ...v.installation, [key]: "0".repeat(64) },
          v.handoff,
          vectors.protocol_artifact,
          v.preparation,
          vectors.destination_backend,
        ),
      Error,
      "initial_analysis_input_invalid",
    );
  }
  await assertRejects(
    () =>
      validateInitialHandoffInstallation(
        v.installation,
        v.handoff,
        vectors.protocol_artifact,
        v.preparation,
        { ...vectors.destination_backend, private_bucket: "different-bucket" },
      ),
    Error,
    "initial_analysis_input_invalid",
  );
  for (const key of Object.keys(v.installation)) {
    const changed: Record<string, unknown> = { ...v.installation };
    delete changed[key];
    await assertRejects(
      () =>
        validateInitialHandoffInstallation(
          changed,
          v.handoff,
          vectors.protocol_artifact,
          v.preparation,
          vectors.destination_backend,
        ),
      Error,
      "initial_analysis_input_invalid",
    );
  }
});
Deno.test("catalog envelope jointly covers every profile rule without assuming audio aliases", async () => {
  for (const v of vectors.valid) {
    const h = structuredClone(v.handoff), rules = v.preparation.spec.rules;
    const objects = rules.reduce(
      (n, r) =>
        n + (r.role === "recording" || r.role === "video_audio" ? 2 : 1),
      0,
    );
    const bytes = rules.reduce(
      (n, r) =>
        n +
        (r.role === "recording" || r.role === "video_audio"
          ? r.limits.source_bytes + r.limits.output_bytes
          : r.role === "raw_video"
          ? r.limits.source_bytes
          : Math.max(r.limits.source_bytes, r.limits.output_bytes)),
      0,
    );
    h.cohort_limits.max_ordinals = rules.length;
    h.cohort_limits.max_unique_objects = objects;
    h.cohort_limits.max_unique_bytes = bytes;
    await assertInitialHandoffCatalogEnvelope(
      v.preparation,
      h,
      vectors.protocol_artifact,
    );
    h.cohort_limits.max_unique_bytes--;
    await assertRejects(
      () =>
        assertInitialHandoffCatalogEnvelope(
          v.preparation,
          h,
          vectors.protocol_artifact,
        ),
      Error,
      "initial_analysis_handoff_catalog_envelope_unsupported",
    );
    if (rules.length > 1) {
      h.cohort_limits.max_unique_bytes = bytes;
      h.cohort_limits.content_type_pairs = h.cohort_limits.content_type_pairs
        .filter((p) => p.kind !== "video" && p.kind !== "audio");
      await assertRejects(() =>
        assertInitialHandoffCatalogEnvelope(
          v.preparation,
          h,
          vectors.protocol_artifact,
        )
      );
    }
  }
});
Deno.test("conservative catalog budget uses rule sums with strict equality and aggregate caps", async () => {
  const v = vectors.valid[0],
    p = structuredClone(v.preparation),
    h = structuredClone(v.handoff);
  const refresh = async () => {
    p.qualification.spec_digest = await initialMediaContractDigest(
      "profile_spec",
      initialCanonicalText(p.spec),
    );
  };
  p.spec.rules[0].limits.wall_ms = 300000 - 45000 - h.total_ms;
  p.spec.limits.wall_ms = 300000;
  await refresh();
  await assertRejects(
    () => assertInitialHandoffCatalogEnvelope(p, h, vectors.protocol_artifact),
    Error,
    "initial_analysis_handoff_catalog_envelope_unsupported",
  );
  p.spec.rules[0].limits.wall_ms--;
  await refresh();
  await assertInitialHandoffCatalogEnvelope(p, h, vectors.protocol_artifact);
  p.spec.limits.source_bytes = p.spec.rules[0].limits.source_bytes - 1;
  await refresh();
  await assertRejects(
    () => assertInitialHandoffCatalogEnvelope(p, h, vectors.protocol_artifact),
    Error,
    "initial_analysis_handoff_catalog_envelope_unsupported",
  );
});
