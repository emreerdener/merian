import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import {
  assertInitialMediaProfileMatches,
  initialMediaContractDigest,
  validateInitialMediaPreparationProfile,
} from "./mediaPreparationProfile.ts";
import { validateInitialMediaAssignment } from "./mediaAssignment.ts";
import { initialPreparationDigest } from "./preparationCandidate.ts";
import vectors from "./fixtures/media-lifecycle-v2.json" with { type: "json" };

Deno.test("dormant whole-cohort profile and saved assignment share exact canonical vectors", async () => {
  for (const v of vectors.valid) {
    assertEquals(
      await validateInitialMediaPreparationProfile(v.profile),
      v.profile_canonical,
      v.name,
    );
    assertEquals(
      await initialMediaContractDigest("profile", v.profile_canonical),
      v.profile_digest,
    );
    await assertInitialMediaProfileMatches(v.candidate, v.profile);
    assertEquals(
      await validateInitialMediaAssignment(v.candidate, v.assignment),
      v.assignment_canonical,
    );
    assertEquals(
      await initialPreparationDigest("assignment", v.assignment_canonical),
      v.assignment_digest,
    );
  }
});
Deno.test("profile identity cannot omit required fields or copy qualification over changed bounds", async () => {
  for (const v of vectors.valid) {
    for (const key of Object.keys(v.profile)) {
      const changed: Record<string, unknown> = structuredClone(v.profile);
      delete changed[key];
      await assertRejects(
        () => validateInitialMediaPreparationProfile(changed),
        Error,
        "initial_analysis_input_invalid",
      );
    }
    for (const key of Object.keys(v.profile.spec)) {
      const changed = structuredClone(v.profile);
      delete (changed.spec as Record<string, unknown>)[key];
      await assertRejects(
        () => validateInitialMediaPreparationProfile(changed),
        Error,
        "initial_analysis_input_invalid",
      );
    }
    const changed = structuredClone(v.profile);
    changed.spec.limits.wall_ms--;
    await assertRejects(
      () => validateInitialMediaPreparationProfile(changed),
      Error,
      "initial_analysis_input_invalid",
    );
  }
});
Deno.test("audio-only qualification cannot authorize mixed or video cohorts", async () => {
  for (const i of [0, 1, 3, 4, 5]) {
    await assertRejects(
      () =>
        assertInitialMediaProfileMatches(
          vectors.valid[i].candidate,
          vectors.valid[2].profile,
        ),
      Error,
      "initial_analysis_preparation_unavailable",
    );
  }
});
Deno.test("fixed profile options and aggregate resource limits bind the complete source cohort", async () => {
  const v = vectors.valid[3];
  for (
    const field of [
      "source_bytes",
      "output_bytes",
      "cpu_ms",
      "heap_bytes",
      "wall_ms",
    ] as const
  ) {
    const p = structuredClone(v.profile);
    p.spec.limits[field] = 1;
    p.qualification.spec_digest = await initialMediaContractDigest(
      "profile_spec",
      initialCanonicalText(p.spec),
    );
    await assertRejects(
      () => assertInitialMediaProfileMatches(v.candidate, p),
      Error,
      "initial_analysis_preparation_unavailable",
    );
  }
  const p = structuredClone(v.profile);
  p.spec.rules.find((r) => r.role === "recording")!.target_sample_rate = 32000;
  p.qualification.spec_digest = await initialMediaContractDigest(
    "profile_spec",
    initialCanonicalText(p.spec),
  );
  await assertRejects(
    () => assertInitialMediaProfileMatches(v.candidate, p),
    Error,
    "initial_analysis_preparation_unavailable",
  );
});
Deno.test("media saved assignment rejects changed identity, source order and destination aliasing", async () => {
  const v = vectors.valid[3];
  const changes = [(a: typeof v.assignment) => {
    a.candidate_digest = "0".repeat(64);
  }, (a: typeof v.assignment) => {
    a.source_plan_digest = "0".repeat(64);
  }, (a: typeof v.assignment) => {
    a.preparation.source_mapping.reverse();
  }, (a: typeof v.assignment) => {
    a.preparation.source_mapping.pop();
  }, (a: typeof v.assignment) => {
    a.preparation.source_mapping[1].object_id =
      a.preparation.source_mapping[0].object_id;
  }, (a: typeof v.assignment) => {
    a.preparation.source_mapping[0].source.source_sha256 = "0".repeat(64);
  }];
  for (const change of changes) {
    const a = structuredClone(v.assignment);
    change(a);
    await assertRejects(
      () => validateInitialMediaAssignment(v.candidate, a),
      Error,
      "initial_analysis_input_invalid",
    );
  }
});
Deno.test("raw MP4 is source-only and cannot acquire a prepared destination or provider output", async () => {
  const v = vectors.valid[5], p = structuredClone(v.profile);
  p.spec.rules.find((r) => r.role === "raw_video")!.limits.output_bytes = 1;
  p.qualification.spec_digest = await initialMediaContractDigest(
    "profile_spec",
    initialCanonicalText(p.spec),
  );
  await assertRejects(
    () => validateInitialMediaPreparationProfile(p),
    Error,
    "initial_analysis_input_invalid",
  );
  const a = structuredClone(v.assignment);
  (a.preparation.source_mapping[2] as Record<string, unknown>)
    .prepared_destination = "00000000-0000-4000-8000-000000000001";
  await assertRejects(
    () => validateInitialMediaAssignment(v.candidate, a),
    Error,
    "initial_analysis_input_invalid",
  );
});

Deno.test("closed allocation responses bind exact saved assignment and convey no authority", async () => {
  const { validateInitialMediaPreparationResponse } = await import(
    "./mediaPreparationResponse.ts"
  );
  for (const v of vectors.valid) {
    const response = {
      version: 2,
      variant: "media_sources",
      outcome: "allocated",
      authority: "none",
      candidate_digest: v.assignment.candidate_digest,
      assignment_digest: v.assignment_digest,
      assignment: v.assignment,
      expires_at: "2026-10-11T00:05:00.123456+00:00",
    };
    assertEquals(
      await validateInitialMediaPreparationResponse(v.candidate, response),
      initialCanonicalText(response),
    );
    for (
      const changed of [
        { ...response, authority: "upload" },
        { ...response, signed_url: "forbidden" },
        { ...response, assignment_digest: "0".repeat(64) },
        { ...response, expires_at: "not-a-date" },
        { ...response, candidate_digest: "0".repeat(64) },
      ]
    ) {
      await assertRejects(
        () => validateInitialMediaPreparationResponse(v.candidate, changed),
        Error,
        "initial_analysis_input_invalid",
      );
    }
    const expired = {
      version: 2,
      variant: "media_sources",
      outcome: "expired",
      authority: "none",
    };
    assertEquals(
      await validateInitialMediaPreparationResponse(v.candidate, expired),
      initialCanonicalText(expired),
    );
    await assertRejects(() =>
      validateInitialMediaPreparationResponse(v.candidate, {
        ...expired,
        assignment: v.assignment,
      })
    );
  }
});
