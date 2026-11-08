import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import fixture from "./fixtures/preparation-v2.json" with { type: "json" };
import initialFixtures from "./fixtures/admission-v1.json" with {
  type: "json",
};
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import {
  initialPreparationDigest,
  validateInitialPreparationCandidate,
  validateInitialSavedAssignment,
} from "./preparationCandidate.ts";

Deno.test("no-media v2 exact candidate and assignment digest vectors", async () => {
  assertEquals(
    validateInitialPreparationCandidate(fixture.candidate),
    fixture.candidate_canonical,
  );
  assertEquals(
    validateInitialSavedAssignment(fixture.assignment),
    fixture.assignment_canonical,
  );
  assertEquals(
    await initialPreparationDigest(
      "preparation-candidate",
      fixture.candidate_canonical,
    ),
    fixture.candidate_digest,
  );
  assertEquals(
    await initialPreparationDigest("assignment", fixture.assignment_canonical),
    fixture.assignment_digest,
  );
  assertNotEquals(
    await initialPreparationDigest("assignment", fixture.candidate_canonical),
    fixture.candidate_digest,
  );
});

Deno.test("candidate is closed and media cannot borrow the no-media case", () => {
  for (const field of Object.keys(fixture.candidate)) {
    const changed: Record<string, unknown> = structuredClone(fixture.candidate);
    delete changed[field];
    assertThrows(() => validateInitialPreparationCandidate(changed));
  }
  assertThrows(() =>
    validateInitialPreparationCandidate({ ...fixture.candidate, profile: null })
  );
  assertThrows(() =>
    validateInitialPreparationCandidate({
      ...fixture.candidate,
      variant: "media",
    })
  );
  for (
    const item of initialFixtures.valid.filter((v) => v.input.media.length > 0)
  ) {
    assertThrows(() =>
      validateInitialPreparationCandidate({
        version: 2,
        variant: "no_media",
        input: item.input,
      })
    );
  }
  assertThrows(() =>
    validateInitialPreparationCandidate({
      ...fixture.candidate,
      input: {
        ...fixture.candidate.input,
        experiment: {
          kind: "audio_comparison",
          plan_sha256: "a".repeat(64),
          slot: 1,
        },
      },
    })
  );
});

Deno.test("ordered text and explicit options remain part of candidate identity", async () => {
  const input = {
    ...fixture.candidate.input,
    route: "identify-multimodal",
    ordered_descriptions: ["Synthetic é", "Synthetic é"],
    owner_timeline: [{ kind: "description", index: 0 }, {
      kind: "description",
      index: 1,
    }],
  };
  const original = validateInitialPreparationCandidate({
    version: 2,
    variant: "no_media",
    input,
  });
  const changed = validateInitialPreparationCandidate({
    version: 2,
    variant: "no_media",
    input: {
      ...input,
      ordered_descriptions: [...input.ordered_descriptions].reverse(),
    },
  });
  assertNotEquals(
    await initialPreparationDigest("preparation-candidate", original),
    await initialPreparationDigest("preparation-candidate", changed),
  );
  assertThrows(() =>
    parseInitialCanonicalText(fixture.candidate_canonical + "\n")
  );
});

Deno.test("every saved assignment field is required and digest-bound", async () => {
  for (const field of Object.keys(fixture.assignment)) {
    const removed: Record<string, unknown> = structuredClone(
      fixture.assignment,
    );
    delete removed[field];
    assertThrows(() => validateInitialSavedAssignment(removed));
    const changed = {
      ...fixture.assignment,
      [field]: "synthetic changed value",
    };
    assertNotEquals(
      await initialPreparationDigest(
        "assignment",
        initialCanonicalText(changed),
      ),
      fixture.assignment_digest,
    );
  }
  assertThrows(() =>
    validateInitialSavedAssignment({ ...fixture.assignment, grant: true })
  );
  assertThrows(() =>
    validateInitialSavedAssignment({
      ...fixture.assignment,
      preparation: {
        kind: "none",
        profile: "validated-wav-darwin-arm64-v1",
        options: null,
      },
    })
  );
  assertThrows(() =>
    validateInitialSavedAssignment({
      ...fixture.assignment,
      preparation: { kind: "none", profile: null },
    })
  );
});
