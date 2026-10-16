import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import { initialCanonicalText as canon } from "./canonical.ts";
import {
  ADMITTED_COMPONENT_LIMITS,
  ADMITTED_MANIFEST_LIMIT,
  ADMITTED_RETAINED_TEXT_LIMIT,
  type AdmittedProofText,
  validAdmittedTimestamp,
  validateAdmittedProof,
} from "./admittedProof.ts";
import vectors from "./fixtures/admitted-proof-v1.json" with { type: "json" };
const clone = (i = 0): AdmittedProofText =>
  structuredClone(vectors.valid[i].components);
const domains = {
  candidate: "preparation-candidate.v2",
  input: "input.v1",
  configuration: "configuration.v1",
  funding: "funding.v1",
  outcome: "preparation-execution.outcome.v2",
  installation: "handoff.installation.v1",
  protocol: "handoff.protocol_artifact.v1",
  destination: "handoff.destination_backend.v1",
  mapping: "handoff.mapping.v2",
  media_binding: "handoff.media_binding.v2",
  accounting: "handoff.accounting.v1",
};
async function hash(domain: string, text: string) {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(
          "merian.initial-analysis." + domain + "\n" + text,
        ),
      ),
    ),
  ].map((x) => x.toString(16).padStart(2, "0")).join("");
}
/** Test-only recommit allows semantic tampering to get past digest checks. */
async function recommit(b: AdmittedProofText) {
  const m = JSON.parse(b.manifest);
  for (const [key, domain] of Object.entries(domains)) {
    const k = key as keyof typeof domains;
    (k === "mapping" || k === "media_binding" ? m.metadata : m.proof)[k] = {
      digest: await hash(domain, b[k]),
      byte_count: new TextEncoder().encode(b[k]).length,
    };
  }
  m.metadata_digest = await hash(
    "handoff.admitted-metadata.v1",
    canon(m.metadata),
  );
  m.proof_digest = await hash("handoff.admitted-proof.v1", canon(m.proof));
  b.manifest = canon(m);
}
/** Propagate source/configuration edits for positive boundaries and coupled-negative controls. */
async function rebind(b: AdmittedProofText) {
  const c = JSON.parse(b.candidate),
    cfg = JSON.parse(b.configuration),
    a = cfg.assignment,
    o = JSON.parse(b.outcome),
    input = JSON.parse(b.input),
    m = JSON.parse(b.manifest),
    mapping = JSON.parse(b.mapping),
    binding = JSON.parse(b.media_binding);
  a.candidate_digest = await hash("preparation-candidate.v2", b.candidate);
  a.source_plan_digest = await hash(
    "media.source_plan.v1",
    canon(c.source_plan),
  );
  b.configuration = canon(cfg);
  m.assignment_digest = await hash("assignment.v2", canon(a));
  for (
    const x of [
      o,
      o.grant,
      o.source_verification,
      o.output_manifest,
      o.resolved_manifest,
      mapping,
      binding,
    ]
  ) x.assignment_digest = m.assignment_digest;
  const sd = await hash(
    "preparation-execution.source_verification.v1",
    canon(o.source_verification),
  );
  o.grant.source_digest = sd;
  o.output_manifest.source_digest = sd;
  o.resolved_manifest.request_digest = await hash(
    "preparation-execution.output_manifest.v1",
    canon(o.output_manifest),
  );
  b.outcome = canon(o);
  const od = await hash("preparation-execution.outcome.v2", b.outcome);
  mapping.outcome_digest = od;
  binding.outcome_digest = od;
  b.mapping = canon(mapping);
  binding.mapping_digest = await hash("handoff.mapping.v2", b.mapping);
  input.ordered_descriptions = c.source_plan.ordered_descriptions;
  input.owner_timeline = c.source_plan.owner_timeline;
  input.admission = c.source_plan.admission;
  b.input = canon(input);
  binding.submission_digest = await hash("input.v1", b.input);
  b.media_binding = canon(binding);
  m.descriptions_digest = await hash(
    "descriptions.v1",
    canon(input.ordered_descriptions),
  );
  m.assets_digest = a.asset_manifest_digest;
  b.manifest = canon(m);
  await recommit(b);
}
Deno.test("admitted proof: all complete shared golden cohorts preserve original bytes and domain-separated receipt", async () => {
  for (const v of vectors.valid) {
    const result = await validateAdmittedProof(v.components);
    assertEquals(result.canonical, v.components);
    assertEquals(result.receiptDigest, v.receipt_digest);
    assertNotEquals(
      result.receiptDigest,
      JSON.parse(v.components.manifest).proof_digest,
    );
  }
  assertEquals(JSON.parse(vectors.valid[6].components.input).media.length, 7);
  assertEquals(
    Object.values(ADMITTED_COMPONENT_LIMITS).reduce((a, b) => a + b, 0) +
      ADMITTED_MANIFEST_LIMIT,
    ADMITTED_RETAINED_TEXT_LIMIT,
  );
});
Deno.test("admitted proof: complete-set and canonical text reject partial, extra, swapped, accessor and corrupted components", async () => {
  for (const key of Object.keys(clone()) as (keyof AdmittedProofText)[]) {
    const missing: Partial<AdmittedProofText> = clone();
    delete missing[key];
    await assertRejects(() => validateAdmittedProof(missing));
    for (const value of [null, "{}", clone()[key] + "\n"]) {
      await assertRejects(() =>
        validateAdmittedProof({ ...clone(), [key]: value })
      );
    }
    const b = clone();
    b[key] = b[key === "input" ? "candidate" : "input"];
    await assertRejects(() => validateAdmittedProof(b));
  }
  await assertRejects(() => validateAdmittedProof({ ...clone(), extra: "{}" }));
  const accessor = clone();
  Object.defineProperty(accessor, "input", {
    get: () => {
      throw new Error("must not invoke accessor");
    },
  });
  await assertRejects(
    () => validateAdmittedProof(accessor),
    Error,
    "initial_analysis_input_invalid",
  );
  const symbol = clone();
  Object.defineProperty(symbol, Symbol("extra"), { value: "{}" });
  await assertRejects(() => validateAdmittedProof(symbol));
  for (
    const [key, limit] of Object.entries({
      ...ADMITTED_COMPONENT_LIMITS,
      manifest: ADMITTED_MANIFEST_LIMIT,
    })
  ) {
    await assertRejects(() =>
      validateAdmittedProof({ ...clone(), [key]: " ".repeat(limit + 1) })
    );
  }
});
Deno.test("admitted proof: manifest refs, identity, lengths and final digest boundaries reject tampering", async () => {
  const base = JSON.parse(clone().manifest);
  for (const key of Object.keys(base)) {
    const b = clone(), m = JSON.parse(b.manifest);
    delete m[key];
    b.manifest = canon(m);
    await assertRejects(() => validateAdmittedProof(b));
  }
  for (const group of ["metadata", "proof"]) {
    for (const role of Object.keys(base[group])) {
      for (const field of ["digest", "byte_count"]) {
        const b = clone(), m = JSON.parse(b.manifest);
        m[group][role][field] = field === "digest"
          ? "f".repeat(64)
          : m[group][role][field] + 1;
        b.manifest = canon(m);
        await assertRejects(() => validateAdmittedProof(b));
      }
    }
  }
  for (
    const field of [
      "owner_id",
      "scan_id",
      "admission_receipt_id",
      "funding_binding_id",
    ]
  ) {
    const b = clone(), m = JSON.parse(b.manifest);
    m[field] = "00000000-0000-4000-8000-000000009999";
    b.manifest = canon(m);
    await assertRejects(() => validateAdmittedProof(b));
  }
  for (
    const field of [
      "assignment_digest",
      "assets_digest",
      "descriptions_digest",
      "phase_window_digest",
      "proof_digest",
      "metadata_digest",
    ]
  ) {
    const b = clone(), m = JSON.parse(b.manifest);
    m[field] = "f".repeat(64);
    b.manifest = canon(m);
    await assertRejects(() => validateAdmittedProof(b));
  }
  const b = clone(),
    m = JSON.parse(b.manifest),
    w = JSON.parse(b.media_binding).phase_window;
  for (
    const timestamp of [
      w.anchor_ms - 1,
      w.cutoffs.admission,
      Number.MAX_SAFE_INTEGER,
    ]
  ) {
    m.authorized_at_ms = timestamp;
    b.manifest = canon(m);
    await assertRejects(() => validateAdmittedProof(b));
  }
  m.authorized_at_ms = w.cutoffs.admission - 1;
  b.manifest = canon(m);
  await validateAdmittedProof(b);
});
Deno.test("admitted proof: all funding and accounting fields are mandatory and reject extra fields", async () => {
  for (const key of ["funding", "accounting"] as const) {
    const root = JSON.parse(clone()[key]);
    const paths = key === "funding"
      ? [[], ["original"]]
      : [[], ["reservation"], ["attempt"], ["charges"], ["charges", "policy"], [
        "charges",
        "links",
        0,
      ], ["complimentary"]];
    for (const path of paths) {
      let obj = root;
      for (const p of path) obj = obj[p];
      for (const field of [...Object.keys(obj), "unexpected"]) {
        const b = clone(), r = JSON.parse(b[key]);
        let target = r;
        for (const p of path) target = target[p];
        if (field === "unexpected") target[field] = 1;
        else delete target[field];
        b[key] = canon(r);
        await recommit(b);
        await assertRejects(() => validateAdmittedProof(b));
      }
    }
  }
});
Deno.test("admitted proof: exact microsecond timestamps validate Gregorian bounds without rounding", async () => {
  for (
    const value of [
      "0001-01-01T00:00:00.000000Z",
      "2000-02-29T23:59:59.999999Z",
      "9999-12-31T23:59:59.999999Z",
    ]
  ) assert(validAdmittedTimestamp(value));
  const invalid = [
    "0000-01-01T00:00:00.000000Z",
    "1900-02-29T00:00:00.000000Z",
    "2026-02-29T00:00:00.000000Z",
    "2026-04-31T00:00:00.000000Z",
    "2026-01-00T00:00:00.000000Z",
    "2026-13-01T00:00:00.000000Z",
    "2026-01-01T24:00:00.000000Z",
    "2026-01-01T00:60:00.000000Z",
    "2026-01-01T00:00:60.000000Z",
    "2026-01-01T00:00:00.000Z",
    "2026-01-01T00:00:00.000000+00:00",
    "2026-01-01T00:00:00.000000Z\n",
    "infinity",
  ];
  for (const value of invalid) {
    assert(!validAdmittedTimestamp(value));
    const b = clone(), a = JSON.parse(b.accounting);
    a.reservation.lease_expires_at = value;
    b.accounting = canon(a);
    await recommit(b);
    await assertRejects(() => validateAdmittedProof(b));
  }
  const b = clone(),
    before = (await validateAdmittedProof(b)).receiptDigest,
    a = JSON.parse(b.accounting);
  a.reservation.lease_expires_at = "2026-10-12T00:20:00.123457Z";
  b.accounting = canon(a);
  await recommit(b);
  assertNotEquals((await validateAdmittedProof(b)).receiptDigest, before);
});
Deno.test("admitted proof: original charge set rejects missing, reordered, rebound, duplicate or malformed links", async () => {
  for (
    const mutation of [
      (a: ReturnType<typeof JSON.parse>) => a.charges.links.pop(),
      (a: ReturnType<typeof JSON.parse>) => a.charges.links.reverse(),
      (a: ReturnType<typeof JSON.parse>) =>
        a.charges.links[2] = a.charges.links[1],
      (a: ReturnType<typeof JSON.parse>) =>
        a.charges.links[1].scope_key = "0".repeat(64),
      (a: ReturnType<typeof JSON.parse>) =>
        a.charges.links[2].scope_key = "A".repeat(64),
      (a: ReturnType<typeof JSON.parse>) =>
        a.charges.links[0].window_seconds = 60,
      (a: ReturnType<typeof JSON.parse>) =>
        a.charges.links[1].window_seconds = 3601,
      (a: ReturnType<typeof JSON.parse>) => a.charges.links[0].delta = 2,
      (a: ReturnType<typeof JSON.parse>) => a.charges.links[0].bucket = " ",
      (a: ReturnType<typeof JSON.parse>) => a.charges.policy.policy_version++,
      (a: ReturnType<typeof JSON.parse>) => a.complimentary = null,
    ]
  ) {
    const b = clone(), a = JSON.parse(b.accounting);
    mutation(a);
    b.accounting = canon(a);
    await recommit(b);
    await assertRejects(() => validateAdmittedProof(b));
  }
  const b = clone(), a = JSON.parse(b.accounting);
  for (const link of a.charges.links) link.bucket = "\u0001".repeat(1024);
  b.accounting = canon(a);
  await recommit(b);
  await validateAdmittedProof(b);
  assert(new TextEncoder().encode(b.accounting).length > 16384);
  a.charges.links[0].bucket += "x";
  b.accounting = canon(a);
  await recommit(b);
  await assertRejects(() => validateAdmittedProof(b));
  const two = clone(), t = JSON.parse(two.accounting);
  t.charges.links.shift();
  two.accounting = canon(t);
  await recommit(two);
  await validateAdmittedProof(two);
});
Deno.test("admitted proof: snapshots every original byte before await and accepts independently bounded text over aggregate cap", async () => {
  const b = clone(), pending = validateAdmittedProof(b);
  for (const key of Object.keys(b) as (keyof AdmittedProofText)[]) {
    b[key] = "{}";
  }
  assertEquals((await pending).canonical, vectors.valid[0].components);
  for (
    const text of [
      "x".repeat(65200),
      "x" + "\u0001".repeat(10870) + "x",
      "🐦".repeat(16300),
    ]
  ) {
    const large = clone(1), c = JSON.parse(large.candidate);
    c.source_plan.ordered_descriptions = Array(16).fill(text);
    c.source_plan.owner_timeline = [
      { kind: "media", index: 0 },
      ...Array.from(
        { length: 16 },
        (_, index) => ({ kind: "description", index }),
      ),
    ];
    large.candidate = canon(c);
    await rebind(large);
    const result = await validateAdmittedProof(large);
    assertEquals(result.canonical.input, large.input);
    assertThrows(() => canon(large));
  }
});
Deno.test("admitted proof: effective provider funding and quota attempt remain distinct and scalar coupling is enforced", async () => {
  const b = clone(1),
    c = JSON.parse(b.candidate),
    cfg = JSON.parse(b.configuration),
    a = cfg.assignment,
    f = JSON.parse(b.funding),
    ac = JSON.parse(b.accounting);
  c.source_plan.admission.expected_processor_permission = "openai";
  Object.assign(a, {
    provider: "openai",
    binding: "openai_photo_v1",
    processor_permission: "openai",
    provider_model: "gpt-6-sol",
    effective_model: "gpt-6-sol",
    minimum_identification_protocol: 4,
  });
  for (
    const k of [
      "provider",
      "binding",
      "processor_permission",
      "provider_model",
      "minimum_identification_protocol",
    ]
  ) ac.attempt[k] = a[k];
  f.original.model = "gpt-6-sol";
  b.candidate = canon(c);
  b.configuration = canon(cfg);
  b.funding = canon(f);
  b.accounting = canon(ac);
  await rebind(b);
  await validateAdmittedProof(b);
  for (const field of ["model", "entitlement_version", "attempt_count"]) {
    for (const value of [null, 0, Number.MAX_SAFE_INTEGER + 1]) {
      const bad = structuredClone(b), funding = JSON.parse(bad.funding);
      funding.original[field] = value;
      try {
        bad.funding = canon(funding);
      } catch {
        continue;
      }
      await recommit(bad);
      await assertRejects(() => validateAdmittedProof(bad));
    }
  }
  const bad = structuredClone(b), funding = JSON.parse(bad.funding);
  funding.original.model = a.quota_model;
  bad.funding = canon(funding);
  await recommit(bad);
  await assertRejects(() => validateAdmittedProof(bad));
  for (
    const [field, value] of [["minimum_identification_protocol", 3], [
      "provider_model",
      "other",
    ], ["model", "other"]]
  ) {
    const bad = clone(),
      cfg = JSON.parse(bad.configuration),
      ac = JSON.parse(bad.accounting);
    if (field === "model") cfg.assignment.quota_model = value;
    else cfg.assignment[field] = value;
    ac.attempt[field] = value;
    bad.configuration = canon(cfg);
    bad.accounting = canon(ac);
    await rebind(bad);
    await assertRejects(() => validateAdmittedProof(bad));
  }
});
Deno.test("admitted proof: shared negative vectors reject including recomputed commitments", async () => {
  for (const v of vectors.invalid) {
    const b = clone(),
      k = v.component as keyof AdmittedProofText,
      r = JSON.parse(b[k]);
    let target = r;
    for (const p of v.path.slice(0, -1)) target = target[p];
    target[v.path.at(-1)!] = v.value;
    if (v.name === "manifest integer overflow") {
      assertThrows(() => canon(r));
      continue;
    }
    b[k] = canon(r);
    if (k !== "manifest") await recommit(b);
    await assertRejects(
      () => validateAdmittedProof(b),
      Error,
      "",
      v.name,
    );
  }
});
Deno.test("admitted proof: original free fallback, optional daily charge and safe entitlement edge are retained without current policy", async () => {
  const b = clone(),
    cfg = JSON.parse(b.configuration),
    f = JSON.parse(b.funding),
    ac = JSON.parse(b.accounting);
  Object.assign(cfg.assignment, {
    effective_plan: "free",
    effective_tier: "free",
    flash_fallback_used: true,
  });
  Object.assign(f.original, {
    effective_plan: "free",
    effective_tier: "free",
    flash_fallback_used: true,
    complimentary_client_scan_id: null,
    entitlement_version: Number.MAX_SAFE_INTEGER,
  });
  ac.attempt.effective_plan = "free";
  ac.charges.policy.effective_plan = "free";
  ac.charges.links.shift();
  ac.complimentary = null;
  b.configuration = canon(cfg);
  b.funding = canon(f);
  b.accounting = canon(ac);
  await rebind(b);
  await validateAdmittedProof(b);
  const bad = clone(),
    c = JSON.parse(bad.configuration),
    funding = JSON.parse(bad.funding);
  c.assignment.flash_fallback_used = true;
  funding.original.flash_fallback_used = true;
  bad.configuration = canon(c);
  bad.funding = canon(funding);
  await rebind(bad);
  await assertRejects(() => validateAdmittedProof(bad));
});
