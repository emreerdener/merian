import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import {
  assertInitialHandoffIssueBudget,
  HANDOFF_PHASES,
  initialHandoffDigest,
  initialHandoffPhaseCutoffs,
  validateInitialHandoffProfile,
  validateInitialHandoffProtocol,
} from "./handoffProfile.ts";
import vectors from "./fixtures/handoff-profile-v1.json" with { type: "json" };

const protocol = vectors.protocol_artifact;
const fresh = () => structuredClone(vectors.valid[0].profile);
const invalid = (value: unknown, artifact: unknown = protocol) =>
  assertRejects(
    () => validateInitialHandoffProfile(value, artifact),
    Error,
    "initial_analysis_input_invalid",
  );

Deno.test("handoff metadata shares canonical profile and composite protocol vectors", async () => {
  assertEquals(
    validateInitialHandoffProtocol(protocol),
    vectors.protocol_canonical,
  );
  assertEquals(
    await initialHandoffDigest("protocol_artifact", vectors.protocol_canonical),
    vectors.protocol_digest,
  );
  for (const v of vectors.valid) {
    assertEquals(
      await validateInitialHandoffProfile(v.profile, protocol),
      v.profile_canonical,
    );
    assertEquals(
      await initialHandoffDigest("profile", v.profile_canonical),
      v.profile_digest,
    );
  }
});

Deno.test("every handoff profile and component field is required and closed", async () => {
  const visit = async (node: Record<string, unknown>, path: string[]) => {
    for (const key of Object.keys(node)) {
      const copy = fresh();
      let target = copy as unknown as Record<string, unknown>;
      for (const segment of path) {
        target = target[segment] as Record<string, unknown>;
      }
      delete target[key];
      await invalid(copy);
      const child = node[key];
      if (
        child !== null && typeof child === "object" && !Array.isArray(child)
      ) {
        await visit(child as Record<string, unknown>, [...path, key]);
      }
    }
    const copy = fresh();
    let target = copy as unknown as Record<string, unknown>;
    for (const segment of path) {
      target = target[segment] as Record<string, unknown>;
    }
    target.authority = "granted";
    await invalid(copy);
  };
  await visit(fresh(), []);
  for (const key of Object.keys(protocol)) {
    const copy: Record<string, unknown> = structuredClone(protocol);
    delete copy[key];
    assertThrows(
      () => validateInitialHandoffProtocol(copy),
      Error,
      "initial_analysis_input_invalid",
    );
  }
  assertThrows(() =>
    validateInitialHandoffProtocol({ ...protocol, installed: true })
  );
});

Deno.test("every protocol component identity and version binds the selected profile", async () => {
  for (const key of Object.keys(protocol).filter((k) => k !== "version")) {
    const copy: Record<string, unknown> = structuredClone(protocol);
    const component = copy[key] as { sha256: string; schema_version: number };
    component.sha256 = "f".repeat(64);
    await invalid(fresh(), copy);
    component.schema_version++;
    assertThrows(() => validateInitialHandoffProtocol(copy));
  }
  await assertRejects(() =>
    initialHandoffDigest("profile", " " + vectors.valid[0].profile_canonical)
  );
  assertEquals(
    initialCanonicalText(fresh()),
    vectors.valid[0].profile_canonical,
  );
});

Deno.test("whole-cohort limits and type pairs cannot widen existing M1 bounds", async () => {
  for (
    const [key, excessive] of [
      ["max_ordinals", 9],
      ["max_unique_objects", 11],
      ["max_unique_bytes", 28625793],
    ] as const
  ) {
    for (const value of [0, excessive, Number.MAX_SAFE_INTEGER, 1.5]) {
      const p = fresh();
      p.cohort_limits[key] = value;
      await invalid(p);
    }
  }
  const empty = fresh();
  empty.cohort_limits.content_type_pairs = [];
  await invalid(empty);
  const duplicate = fresh();
  duplicate.cohort_limits.content_type_pairs = [
    duplicate.cohort_limits.content_type_pairs[0],
    duplicate.cohort_limits.content_type_pairs[0],
  ];
  await invalid(duplicate);
  for (const kind of ["image", "audio", "video"]) {
    const p = fresh();
    const pair = p.cohort_limits.content_type_pairs.find((r) =>
      r.kind === kind
    )!;
    pair.prepared_content_type = kind === "video" ? "video/mp4" : null;
    await invalid(p);
  }
  const crossType = fresh();
  crossType.cohort_limits.content_type_pairs[0].prepared_content_type =
    "image/png";
  await invalid(crossType);
  const crossKind = fresh();
  crossKind.cohort_limits.content_type_pairs[0].kind = "audio";
  await invalid(crossKind);
  for (const key of ["alias_policy", "video_policy"] as const) {
    const p = fresh();
    p.cohort_limits[key] = "deduplicate_all";
    await invalid(p);
  }
});

Deno.test("budget includes every positive phase exactly once and rejects unsafe values", async () => {
  for (const phase of HANDOFF_PHASES) {
    for (
      const ms of [0, -1, 0.5, NaN, Infinity, 300000, Number.MAX_SAFE_INTEGER]
    ) {
      const p = fresh();
      p.phase_ms[phase] = ms;
      await invalid(p);
    }
    const p = fresh();
    p.phase_ms[phase]++;
    await invalid(p);
    p.total_ms++;
    await validateInitialHandoffProfile(p, protocol);
  }
  for (const total of [7, 300000, fresh().total_ms - 1]) {
    const p = fresh();
    p.total_ms = total;
    await invalid(p);
  }
});

Deno.test("issuance reserves 45s plus original preparation and pinned full handoff suffix", async () => {
  const b = vectors.budget;
  await assertInitialHandoffIssueBudget(
    fresh(),
    protocol,
    b.anchor_ms,
    b.expires_at_ms,
    b.preparation_wall_ms,
  );
  for (const remaining of [b.issue_required_ms - 1, b.issue_required_ms]) {
    await assertRejects(
      () =>
        assertInitialHandoffIssueBudget(
          fresh(),
          protocol,
          b.anchor_ms,
          b.anchor_ms + remaining,
          b.preparation_wall_ms,
        ),
      Error,
      "initial_analysis_handoff_budget_unavailable",
    );
  }
  await assertInitialHandoffIssueBudget(
    fresh(),
    protocol,
    b.anchor_ms,
    b.anchor_ms + b.issue_required_ms + 1,
    b.preparation_wall_ms,
  );
  // The former unqualified 35s suffix cannot substitute for this 80s profile.
  await assertRejects(() =>
    assertInitialHandoffIssueBudget(
      fresh(),
      protocol,
      b.anchor_ms,
      b.anchor_ms + 45000 + b.preparation_wall_ms + 35001,
      b.preparation_wall_ms,
    )
  );
});

Deno.test("admission cutoffs preserve fixed ordering and strict original expiry without epoch overflow", async () => {
  const b = vectors.budget;
  assertEquals(
    await initialHandoffPhaseCutoffs(
      fresh(),
      protocol,
      b.anchor_ms,
      b.expires_at_ms,
    ),
    b.cutoffs,
  );
  const total = fresh().total_ms;
  await assertRejects(
    () =>
      initialHandoffPhaseCutoffs(
        fresh(),
        protocol,
        b.anchor_ms,
        b.anchor_ms + total,
      ),
    Error,
    "initial_analysis_handoff_budget_unavailable",
  );
  const end = Number.MAX_SAFE_INTEGER, start = end - total - 1;
  const cutoffs = await initialHandoffPhaseCutoffs(
    fresh(),
    protocol,
    start,
    end,
  );
  assertEquals(cutoffs.protocol_margin, end - 1);
  await assertInitialHandoffIssueBudget(
    fresh(),
    protocol,
    end - b.issue_required_ms - 1,
    end,
    b.preparation_wall_ms,
  );
  await assertRejects(
    () =>
      assertInitialHandoffIssueBudget(
        fresh(),
        protocol,
        end - b.issue_required_ms,
        end,
        b.preparation_wall_ms,
      ),
    Error,
    "initial_analysis_handoff_budget_unavailable",
  );
});

Deno.test("metadata helpers reject fabricated windows, missing profiles and invalid wall bounds", async () => {
  const b = vectors.budget;
  for (
    const [now, expiry] of [
      [-0, 300000],
      [-1, 10],
      [1, 1],
      [2, 1],
      [0, 300001],
      [NaN, 4],
      [1, Infinity],
      [1.5, 2],
      [0, Number.MAX_SAFE_INTEGER + 1],
    ]
  ) {
    await assertRejects(
      () => initialHandoffPhaseCutoffs(fresh(), protocol, now, expiry),
      Error,
      "initial_analysis_input_invalid",
    );
  }
  for (const wall of [0, -1, 0.5, Infinity, 300001]) {
    await assertRejects(
      () =>
        assertInitialHandoffIssueBudget(
          fresh(),
          protocol,
          b.anchor_ms,
          b.expires_at_ms,
          wall,
        ),
      Error,
      "initial_analysis_input_invalid",
    );
  }
  await invalid(null);
  await invalid(fresh(), null);
  const old = fresh() as unknown as Record<string, unknown>;
  delete old.protocol_artifact_digest;
  await invalid(old);
});
