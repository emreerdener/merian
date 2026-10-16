import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import { initialMediaContractDigest } from "./mediaPreparationProfile.ts";
import { validateInitialMediaSourceCandidate } from "./mediaSourceCandidate.ts";
import { initialCanonicalText } from "./canonical.ts";
import { initialPreparationDigest } from "./preparationCandidate.ts";
import { validateInitialMediaAssignment } from "./mediaAssignment.ts";
import {
  executionDigest,
  preparationContext,
  validatePreparationReply,
} from "./preparationExecutionContract.ts";
import {
  qualifiedExecutionCanonical,
  qualifiedOutcomeDigest,
  qualifiedPreparationContext,
  validateQualifiedGrant,
  validateQualifiedMediaAssignment,
  validateQualifiedOutcome,
  validateQualifiedReply,
} from "./qualifiedPreparationCodec.ts";
import vectors from "./fixtures/qualified-preparation-v3.json" with {
  type: "json",
};
const clone = <T>(v: T): T => structuredClone(v);
Deno.test("qualified codecs: six original v3 assignments and mixed-version v2 outcomes match shared bytes", async () => {
  for (const v of vectors.valid) {
    assertEquals(
      await validateQualifiedMediaAssignment(
        v.candidate,
        v.assignment,
        v.catalog,
      ),
      v.assignment_canonical,
    );
    assertEquals(
      await initialPreparationDigest("assignment", v.assignment_canonical),
      v.assignment_digest,
    );
    const ctx = await qualifiedPreparationContext(
      v.outcome.scan_id,
      v.candidate,
      v.assignment,
      v.catalog,
      v.original_expires_at_ms,
    );
    assertEquals(
      await validateQualifiedOutcome(ctx, v.outcome),
      v.outcome_canonical,
    );
    assertEquals(
      await qualifiedOutcomeDigest(v.outcome_canonical),
      v.outcome_digest,
    );
    assertNotEquals(
      await executionDigest("outcome", v.outcome_canonical),
      v.outcome_digest,
    );
    await assertRejects(() =>
      validateInitialMediaAssignment(v.candidate, v.assignment)
    );
    for (
      const k of [
        "source_verification",
        "output_manifest",
        "resolved_manifest",
      ] as const
    ) {
      const changed = clone(v.outcome);
      changed[k].version = 2;
      await assertRejects(() => validateQualifiedOutcome(ctx, changed));
    }
  }
});
Deno.test("qualified codecs: every new qualification field is required and cross-bound", async () => {
  const v = vectors.valid[0],
    ctx = await qualifiedPreparationContext(
      v.outcome.scan_id,
      v.candidate,
      v.assignment,
      v.catalog,
      v.original_expires_at_ms,
    );
  for (const k of Object.keys(v.assignment.handoff)) {
    const a = JSON.parse(initialCanonicalText(v.assignment));
    delete a.handoff[k];
    await assertRejects(() =>
      validateQualifiedMediaAssignment(v.candidate, a, v.catalog)
    );
  }
  for (
    const k of [
      "handoff_profile_digest",
      "handoff_installation_digest",
      "protocol_artifact_digest",
      "handoff_total_ms",
      "preparation_wall_ms",
      "preparation_expires_at_ms",
    ]
  ) {
    const g = JSON.parse(initialCanonicalText(v.outcome.grant));
    delete g[k];
    assertThrows(() => validateQualifiedGrant(ctx, v.source_digest, g));
    g[k] =
      typeof v.outcome.grant[k as keyof typeof v.outcome.grant] === "number"
        ? 1
        : "0".repeat(64);
    assertThrows(() => validateQualifiedGrant(ctx, v.source_digest, g));
  }
  const a = clone(v.assignment);
  a.handoff.installation_digest = "0".repeat(64);
  await assertRejects(() =>
    validateQualifiedMediaAssignment(v.candidate, a, v.catalog)
  );
  const extra = { ...v.outcome.grant, extra: true };
  assertThrows(() => validateQualifiedGrant(ctx, v.source_digest, extra));
  for (const version of [1, 3]) {
    assertThrows(() =>
      validateQualifiedGrant(ctx, v.source_digest, {
        ...v.outcome.grant,
        version,
      })
    );
  }
});
Deno.test("qualified codecs: original expiry is strict and cannot be supplied by grant payload", async () => {
  const v = vectors.valid[0],
    g = v.outcome.grant,
    e = g.issued_at_ms + 45000 + g.preparation_wall_ms + g.handoff_total_ms;
  const ctx = await qualifiedPreparationContext(
    v.outcome.scan_id,
    v.candidate,
    v.assignment,
    v.catalog,
    e,
  );
  assertThrows(() =>
    validateQualifiedGrant(ctx, v.source_digest, {
      ...g,
      preparation_expires_at_ms: e,
    })
  );
  const next = await qualifiedPreparationContext(
    v.outcome.scan_id,
    v.candidate,
    v.assignment,
    v.catalog,
    e + 1,
  );
  validateQualifiedGrant(next, v.source_digest, {
    ...g,
    preparation_expires_at_ms: e + 1,
  });
  assertThrows(() =>
    validateQualifiedGrant(next, v.source_digest, {
      ...g,
      preparation_expires_at_ms: e + 2,
    })
  );
  await assertRejects(() =>
    qualifiedPreparationContext(
      v.outcome.scan_id,
      v.candidate,
      v.assignment,
      v.catalog,
      Number.MAX_SAFE_INTEGER + 1,
    )
  );
});
Deno.test("qualified reply codec: refusal never widens v1 and retained nested receipt versions stay exact", () => {
  const held = {
    version: 2,
    outcome: "held",
    authority: "none",
    reason: "handoff_qualification_unavailable",
  };
  assertEquals(validateQualifiedReply(held), held);
  assertThrows(() => validatePreparationReply(held));
  const v = vectors.valid[0],
    reply = {
      version: 2,
      outcome: "outcome_ready",
      result: v.outcome,
      digest: v.outcome_digest,
    };
  validateQualifiedReply(reply);
  assertThrows(() => validateQualifiedReply({ ...reply, version: 1 }));
  const changed = clone(reply);
  changed.result.grant.version = 1;
  assertThrows(() => validateQualifiedReply(changed));
  assertThrows(() =>
    qualifiedExecutionCanonical("outcome", { ...v.outcome, version: 1 })
  );
});
Deno.test("qualified async validation snapshots caller declarations and receipt context", async () => {
  const v = clone(vectors.valid[0]);
  const pending = validateQualifiedMediaAssignment(
    v.candidate,
    v.assignment,
    v.catalog,
  );
  v.catalog.installation.profile_digest = "0".repeat(64);
  assertEquals(await pending, vectors.valid[0].assignment_canonical);
  const original = vectors.valid[0];
  const ctx = await qualifiedPreparationContext(
    original.outcome.scan_id,
    original.candidate,
    original.assignment,
    original.catalog,
    original.original_expires_at_ms,
  );
  const outcomePending = validateQualifiedOutcome(ctx, original.outcome);
  ctx.handoffProfileDigest = "0".repeat(64);
  assertEquals(await outcomePending, original.outcome_canonical);
});

Deno.test("qualified context: independently bounded large plain, escaped and non-BMP text survives composition", async () => {
  for (
    const text of [
      "x".repeat(65200),
      "x" + "\u0001".repeat(10870) + "x",
      "🐦".repeat(16300),
    ]
  ) {
    const v = clone(vectors.valid[1]);
    v.candidate.source_plan.ordered_descriptions = Array.from(
      { length: 16 },
      () => text,
    );
    v.candidate.source_plan.owner_timeline = [
      { kind: "media", index: 0 },
      ...Array.from(
        { length: 16 },
        (_, index) => ({ kind: "description", index }),
      ),
    ];
    const candidateText = validateInitialMediaSourceCandidate(v.candidate);
    v.assignment.candidate_digest = await initialPreparationDigest(
      "preparation-candidate",
      candidateText,
    );
    v.assignment.source_plan_digest = await initialMediaContractDigest(
      "source_plan",
      initialCanonicalText(v.candidate.source_plan),
    );
    // This was an accidental aggregate ceiling, not an existing component limit.
    assertThrows(() =>
      initialCanonicalText({
        candidate: v.candidate,
        assignment: v.assignment,
        catalog: v.catalog,
      })
    );
    const expectedAssignment = initialCanonicalText(v.assignment);
    assertEquals(
      await validateQualifiedMediaAssignment(
        v.candidate,
        v.assignment,
        v.catalog,
      ),
      expectedAssignment,
    );
    const pending = qualifiedPreparationContext(
      v.outcome.scan_id,
      v.candidate,
      v.assignment,
      v.catalog,
      v.original_expires_at_ms,
    );
    // All caller-owned components were captured before the first await.
    v.candidate.source_plan.ordered_descriptions[0] = "mutated";
    v.assignment.candidate_digest = "0".repeat(64);
    v.catalog.preparation.spec.runtime.version = "mutated";
    const ctx = await pending;
    assertEquals(
      ctx.receipts.candidate.source_plan.ordered_descriptions,
      Array.from({ length: 16 }, () => text),
    );
    assertEquals(
      ctx.receipts.assignment_digest,
      await initialPreparationDigest("assignment", expectedAssignment),
    );
    assertNotEquals(ctx.receipts.profile.spec.runtime.version, "mutated");
    // Isolate the negative from the deliberately mutated caller objects above.
    const over = clone(vectors.valid[1].candidate);
    over.source_plan.ordered_descriptions = Array.from(
      { length: 16 },
      () => "x".repeat(65530),
    );
    over.source_plan.owner_timeline = [
      { kind: "media", index: 0 },
      ...Array.from(
        { length: 16 },
        (_, index) => ({ kind: "description", index }),
      ),
    ];
    assertThrows(() => initialCanonicalText(over));
    assertThrows(() => validateInitialMediaSourceCandidate(over));
  }
});

Deno.test("direct preparation context snapshots all independently bounded inputs before awaiting", async () => {
  const v = clone(vectors.valid[1]);
  const text = "x".repeat(65400);
  v.candidate.source_plan.ordered_descriptions = Array.from(
    { length: 16 },
    () => text,
  );
  v.candidate.source_plan.owner_timeline = [
    { kind: "media", index: 0 },
    ...Array.from(
      { length: 16 },
      (_, index) => ({ kind: "description", index }),
    ),
  ];
  v.assignment.candidate_digest = await initialPreparationDigest(
    "preparation-candidate",
    validateInitialMediaSourceCandidate(v.candidate),
  );
  v.assignment.source_plan_digest = await initialMediaContractDigest(
    "source_plan",
    initialCanonicalText(v.candidate.source_plan),
  );
  const { handoff: _handoff, ...assignment } = v.assignment;
  assignment.version = 2;
  const profile = v.catalog.preparation;
  const expectedProfile = initialCanonicalText(profile);
  const expectedAssignment = await validateInitialMediaAssignment(
    v.candidate,
    assignment,
  );
  assertThrows(() =>
    initialCanonicalText({ candidate: v.candidate, assignment, profile })
  );
  const pending = preparationContext(
    v.outcome.scan_id,
    v.candidate,
    assignment,
    profile,
  );
  v.candidate.source_plan.ordered_descriptions[0] = "mutated";
  assignment.candidate_digest = "0".repeat(64);
  assignment.preparation.source_mapping[0].source.source_sha256 = "0".repeat(
    64,
  );
  profile.spec.runtime.version = "mutated";
  const result = await pending;
  assertEquals(
    result.candidate.source_plan.ordered_descriptions,
    Array.from({ length: 16 }, () => text),
  );
  assertEquals(initialCanonicalText(result.assignment), expectedAssignment);
  assertEquals(initialCanonicalText(result.profile), expectedProfile);
  assertEquals(
    result.assignment_digest,
    await initialPreparationDigest("assignment", expectedAssignment),
  );
});
