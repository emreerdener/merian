import { assertEquals, assertNotEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import {
  admissionMetadataDigest,
  type AdmissionMetadataKind,
  validateInitialAdmissionMetadata,
} from "./admissionMetadata.ts";
import { qualifiedOutcomeDigest } from "./qualifiedPreparationCodec.ts";
import originals from "./fixtures/qualified-preparation-v3.json" with {
  type: "json",
};
import vectors from "./fixtures/admission-metadata-v1.json" with {
  type: "json",
};
const allOriginals = [...originals.valid, ...vectors.extra_originals];
function bundle(index = 0) {
  const v = vectors.valid[index], o = allOriginals[v.original_index];
  return JSON.parse(JSON.stringify({
    // Test-only wrapper uses API camelCase; wire values validate separately.
    original: {
      candidate: o.candidate,
      assignment: o.assignment,
      catalog: o.catalog,
      outcome: o.outcome,
      originalExpiresAtMs: o.original_expires_at_ms,
    },
    scope: v.scope,
    metadata: v.metadata,
  }));
}
const run = (b: ReturnType<typeof bundle>) =>
  validateInitialAdmissionMetadata(b.original, b.scope, b.metadata);
async function rebind(b: ReturnType<typeof bundle>) {
  const m = b.metadata;
  const outcome = await qualifiedOutcomeDigest(
    initialCanonicalText(b.original.outcome),
  );
  m.mapping.outcome_digest = outcome;
  m.media_binding.outcome_digest = outcome;
  m.media_binding.mapping_digest = await admissionMetadataDigest(
    "mapping",
    initialCanonicalText(m.mapping),
  );
  m.media_binding.phase_window = structuredClone(m.phase_window);
  m.media_binding.phase_window_digest = await admissionMetadataDigest(
    "phase_window",
    initialCanonicalText(m.phase_window),
  );
}
Deno.test("admission metadata: shared originals, maximum video topology, aliases and exact text match canonical vectors", async () => {
  for (const [i, v] of vectors.valid.entries()) {
    const result = await run(bundle(i));
    assertEquals(result.canonicalInput, v.input_canonical);
    assertEquals(result.submissionDigest, v.submission_digest);
    assertEquals(result.descriptionsDigest, v.descriptions_digest);
    assertEquals(
      result.canonicalPhaseWindow,
      initialCanonicalText(v.metadata.phase_window),
    );
    assertEquals(result.phaseWindowDigest, v.phase_window_digest);
    assertEquals(
      result.canonicalMapping,
      initialCanonicalText(v.metadata.mapping),
    );
    assertEquals(result.mappingDigest, v.mapping_digest);
    assertEquals(
      result.canonicalMediaBinding,
      initialCanonicalText(v.metadata.media_binding),
    );
    assertEquals(result.mediaBindingDigest, v.media_binding_digest);
  }
  assertEquals(vectors.valid[6].input.media.length, 7);
  assertEquals(vectors.valid[6].input.ordered_descriptions, [
    "line one\nCafe\u0301 🐦",
  ]);
  assertEquals(vectors.valid[7].metadata.mapping.objects.length, 1);
  assertEquals(vectors.valid[8].metadata.mapping.objects.length, 2);
});
Deno.test("admission metadata: missing, extra and cross-version fields reject in every closed root", async () => {
  for (const key of ["phase_window", "mapping", "media_binding"]) {
    for (const field of Object.keys(bundle().metadata[key])) {
      const b = bundle();
      delete b.metadata[key][field];
      await assertRejects(() => run(b));
    }
    const extra = bundle();
    extra.metadata[key].unrecognized = true;
    await assertRejects(() => run(extra));
    const version = bundle();
    version.metadata[key].version = 99;
    await assertRejects(() => run(version));
    const enclosing = bundle();
    enclosing.metadata[key].admission_receipt_digest = "a".repeat(64);
    await assertRejects(() => run(enclosing));
  }
  const source = bundle();
  source.metadata.mapping.items[0].source = null;
  await assertRejects(() => run(source));
});
Deno.test("admission metadata: identities, generation and every digest bind original values", async () => {
  for (const key of ["phase_window", "mapping", "media_binding"]) {
    for (const [field, value] of Object.entries(bundle().metadata[key])) {
      if (typeof value !== "string") continue;
      const b = bundle();
      b.metadata[key][field] = field.endsWith("digest")
        ? "f".repeat(64)
        : "00000000-0000-4000-8000-000000009999";
      await assertRejects(() => run(b));
    }
  }
  const original = bundle();
  original.original.outcome.source_verification.entries[0].bytes.sha256 = "f"
    .repeat(64);
  await assertRejects(() => run(original));
});
Deno.test("admission metadata: mappings reject cross-ordinal alias, omitted union, ordering, mismatched bytes and original source collision", async () => {
  for (
    const mutation of [
      (b: ReturnType<typeof bundle>) => {
        b.metadata.mapping.items[1].source.destination_object_id =
          b.metadata.mapping.items[0].source.destination_object_id;
      },
      (b: ReturnType<typeof bundle>) => {
        b.metadata.mapping.items.reverse();
      },
      (b: ReturnType<typeof bundle>) => {
        b.metadata.mapping.objects.reverse();
      },
      (b: ReturnType<typeof bundle>) => {
        b.metadata.mapping.objects.pop();
      },
      (b: ReturnType<typeof bundle>) => {
        b.metadata.mapping.objects[0].bytes.sha256 = "f".repeat(64);
      },
      (b: ReturnType<typeof bundle>) => {
        b.metadata.mapping.items[0].source.bytes.byte_count++;
      },
      (b: ReturnType<typeof bundle>) => {
        b.metadata.mapping.items[0].source.original_object_id =
          b.metadata.mapping.items[1].source.original_object_id;
      },
      (b: ReturnType<typeof bundle>) => {
        b.metadata.mapping.items[0].source.destination_object_id =
          b.original.outcome.source_verification.entries[6].object_id;
      },
      (b: ReturnType<typeof bundle>) => {
        b.metadata.mapping.items[6].prepared = structuredClone(
          b.metadata.mapping.items[0].prepared,
        );
      },
    ]
  ) {
    const b = bundle(6);
    mutation(b);
    await rebind(b);
    await assertRejects(() => run(b));
  }
  // Equal bytes with distinct original audio IDs must alias inside one ordinal.
  const equal = bundle(7);
  equal.metadata.mapping.items[0].prepared.destination_object_id =
    "00000000-0000-4000-8000-000000008888";
  await rebind(equal);
  await assertRejects(() => run(equal));
  const different = bundle(8);
  different.metadata.mapping.items[0].prepared.destination_object_id =
    different.metadata.mapping.items[0].source.destination_object_id;
  await rebind(different);
  await assertRejects(() => run(different));
});
Deno.test("admission metadata: cutoffs use strict original expiry and safe-integer arithmetic", async () => {
  for (const phase of Object.keys(bundle().metadata.phase_window.cutoffs)) {
    for (const delta of [-1, 1]) {
      const b = bundle();
      b.metadata.phase_window.cutoffs[phase] += delta;
      await rebind(b);
      await assertRejects(() => run(b));
    }
  }
  const before = bundle();
  before.metadata.phase_window.anchor_ms =
    before.original.outcome.grant.issued_at_ms - 1;
  await rebind(before);
  await assertRejects(() => run(before));
  for (const remaining of [80000, 79999, 80001]) {
    const b = bundle(), w = b.metadata.phase_window;
    const delta = w.original_expires_at_ms - remaining - w.anchor_ms;
    w.anchor_ms += delta;
    for (const phase of Object.keys(w.cutoffs)) w.cutoffs[phase] += delta;
    await rebind(b);
    if (remaining > 80000) await run(b);
    else {await assertRejects(
        () => run(b),
        Error,
        "initial_analysis_handoff_budget_unavailable",
      );}
  }
  const b = bundle(),
    delta = Number.MAX_SAFE_INTEGER - b.original.originalExpiresAtMs;
  b.original.originalExpiresAtMs += delta;
  const grant = b.original.outcome.grant;
  for (
    const field of [
      "issued_at_ms",
      "execution_deadline_ms",
      "registration_deadline_ms",
      "outcome_deadline_ms",
      "preparation_expires_at_ms",
    ]
  ) grant[field] += delta;
  b.metadata.phase_window.anchor_ms += delta;
  b.metadata.phase_window.original_expires_at_ms += delta;
  for (const phase of Object.keys(b.metadata.phase_window.cutoffs)) {
    b.metadata.phase_window.cutoffs[phase] += delta;
  }
  await rebind(b);
  await run(b);
  b.metadata.phase_window.anchor_ms = Number.MAX_SAFE_INTEGER + 1;
  await assertRejects(() => run(b));
});
Deno.test("admission metadata: mutation after first await cannot change any returned identity", async () => {
  const b = bundle(6), expected = vectors.valid[6];
  const pending = run(b);
  b.scope.owner_id = "00000000-0000-4000-8000-000000008888";
  b.original.candidate.source_plan.ordered_descriptions[0] = "changed";
  b.original.assignment.handoff.profile.total_ms++;
  b.original.catalog.preparation.spec.limits.source_bytes++;
  b.original.outcome.retained.length = 0;
  b.original.originalExpiresAtMs++;
  b.metadata.phase_window.anchor_ms++;
  b.metadata.mapping.objects.length = 0;
  b.metadata.media_binding.phase_window.anchor_ms++;
  const result = await pending;
  assertEquals(result.canonicalInput, expected.input_canonical);
  assertEquals(result.mediaBindingDigest, expected.media_binding_digest);
});
Deno.test("admission metadata: hash API rejects noncanonical text, unsupported domains and excessive structures", async () => {
  const v = vectors.valid[0];
  await assertRejects(() =>
    admissionMetadataDigest("mapping", JSON.stringify(v.metadata.mapping))
  );
  await assertRejects(() =>
    admissionMetadataDigest(
      "admitted_receipt" as AdmissionMetadataKind,
      initialCanonicalText(v.metadata.mapping),
    )
  );
  const b = bundle();
  b.metadata.mapping.items = Array(9).fill(b.metadata.mapping.items[0]);
  await assertRejects(() => run(b));
  const objects = bundle();
  objects.metadata.mapping.objects = Array(11).fill(
    objects.metadata.mapping.objects[0],
  );
  await assertRejects(() => run(objects));
  assertNotEquals(v.phase_window_digest, v.media_binding_digest);
});
