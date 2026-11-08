import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import vectors from "./fixtures/media-source-v2.json" with { type: "json" };
import inputVectors from "./fixtures/admission-v1.json" with { type: "json" };
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import {
  initialPreparationDigest,
  validateInitialPreparationCandidate,
  validateInitialSavedAssignment,
} from "./preparationCandidate.ts";
import { validateInitialInput } from "./schema.ts";
import { validateInitialMediaSourceCandidate } from "./mediaSourceCandidate.ts";

function replaceAt(
  value: unknown,
  path: readonly string[],
  replacement: unknown,
): unknown {
  if (path.length === 0) return replacement;
  if (Array.isArray(value)) {
    return value.map((item, index) =>
      String(index) === path[0]
        ? replaceAt(item, path.slice(1), replacement)
        : item
    );
  }
  if (value !== null && typeof value === "object") {
    const fields = value as Record<string, unknown>;
    return {
      ...fields,
      [path[0]]: replaceAt(fields[path[0]], path.slice(1), replacement),
    };
  }
  throw new Error("invalid synthetic vector path");
}

Deno.test("source declarations preserve exact canonical identity without prepared tuples", async () => {
  for (const item of vectors.valid) {
    assertEquals(
      validateInitialMediaSourceCandidate(item.candidate),
      item.canonical,
      item.name,
    );
    assertEquals(
      await initialPreparationDigest("preparation-candidate", item.canonical),
      item.digest,
    );
    assertThrows(() => parseInitialCanonicalText(item.canonical + "\n"));
    assertThrows(() => validateInitialInput(item.candidate));
    assertThrows(() => validateInitialPreparationCandidate(item.candidate));
    assertThrows(() => validateInitialSavedAssignment(item.candidate));
  }
});

Deno.test("source contract rejects fabricated outputs, authority, associations and bounds", () => {
  for (const item of vectors.invalid) {
    const changed = replaceAt(
      vectors.valid[item.base].candidate,
      item.path,
      item.value,
    );
    assertThrows(
      () => validateInitialMediaSourceCandidate(changed),
      Error,
      "initial_analysis_input_invalid",
      item.name,
    );
  }
  const original = vectors.valid[0].candidate;
  for (const [name, value] of Object.entries(original)) {
    const removed: Record<string, unknown> = { ...original };
    delete removed[name];
    assertThrows(() => validateInitialMediaSourceCandidate(removed));
    assertThrows(() =>
      validateInitialMediaSourceCandidate({ ...original, [name]: null })
    );
    assertNotEquals(value, undefined);
  }
  for (const name of Object.keys(original.source_plan.sources[0])) {
    const changed = structuredClone(original);
    const source: Record<string, unknown> = changed.source_plan.sources[0];
    delete source[name];
    assertThrows(() => validateInitialMediaSourceCandidate(changed));
  }
});

Deno.test("source declaration fields remain equal to original accepted input semantics", () => {
  const originals = inputVectors.valid.filter((item) =>
    item.input.media.length > 0
  );
  assertEquals(originals.length, vectors.valid.length);
  for (let index = 0; index < originals.length; index++) {
    const { media, ...plan } = originals[index].input;
    const sources = media.map((
      { content_type: _type, byte_count: _count, sha256: _hash, ...source },
    ) => ({
      ...source,
      prepared_output: { state: "unresolved" },
    }));
    assertEquals(vectors.valid[index].candidate.source_plan, {
      ...plan,
      sources,
    });
  }
});

Deno.test("source identity binds order, exact text, source bytes, options and context", async () => {
  const original = vectors.valid[3].candidate;
  const changes = [
    replaceAt(
      original,
      ["source_plan", "ordered_descriptions", "0"],
      "Synthetic é",
    ),
    replaceAt(
      original,
      ["source_plan", "sources", "0", "source_sha256"],
      "b".repeat(64),
    ),
    replaceAt(
      original,
      ["source_plan", "sources", "0", "source_byte_count"],
      69,
    ),
    replaceAt(
      original,
      ["source_plan", "context", "device_locale"],
      "synthetic",
    ),
    replaceAt(original, ["source_plan", "options", "geoprivacy"], "obscured"),
    replaceAt(
      original,
      ["source_plan", "owner_timeline"],
      [
        original.source_plan.owner_timeline[0],
        original.source_plan.owner_timeline[2],
        original.source_plan.owner_timeline[1],
        original.source_plan.owner_timeline[3],
      ],
    ),
  ];
  for (const changed of changes) {
    const text = validateInitialMediaSourceCandidate(changed);
    assertNotEquals(
      await initialPreparationDigest("preparation-candidate", text),
      vectors.valid[3].digest,
    );
  }
  assertNotEquals(
    initialCanonicalText(original),
    initialCanonicalText(changes[0]),
  );
});
