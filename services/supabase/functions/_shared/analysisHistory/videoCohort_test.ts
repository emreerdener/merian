import { assert, assertEquals, assertThrows } from "@std/assert";
import inputs from "./fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import inventories from "./fixtures/video-cohort-inventory-v1.json" with {
  type: "json",
};
import {
  matchPreparedVideoCohortItems,
  preparedVideoCohortItems,
} from "./videoCohort.ts";
import { sourceReservationCanonicalBytes } from "./sourceFingerprint.ts";

Deno.test("held video inventory matches fixed audio/silent/Unicode ordering and owns metadata", () => {
  inputs.forEach((vector, i) => {
    const input = structuredClone(vector.input);
    const actual = preparedVideoCohortItems(input);
    assertEquals<unknown>(actual, inventories[i].items);
    assert(Object.isFrozen(actual) && actual.every(Object.isFrozen));
    assertEquals(
      matchPreparedVideoCohortItems(inventories[i].items, input),
      actual,
    );
    input.evidence_manifest.provenance.source.sha256 = "0".repeat(64);
    assertEquals<unknown>(actual, inventories[i].items);
    assertThrows(() => sourceReservationCanonicalBytes(vector.input));
  });
});

Deno.test("held video inventory rejects partial, reordered, ambiguous and cross-input coverage", () => {
  const input = inputs[0].input, items = inventories[0].items;
  for (
    const value of [
      null,
      {},
      [],
      items.slice(1),
      [...items, items[0]],
      [...items].reverse(),
      items.map((x, i) => i === 1 ? items[2] : i === 2 ? items[1] : x),
      items.map((x, i) =>
        i === 0 ? { ...x, object_id: input.observation_id } : x
      ),
      inventories[1].items,
    ]
  ) assertThrows(() => matchPreparedVideoCohortItems(value, input));
  for (let index = 0; index < items.length; index++) {
    for (const key of Object.keys(items[index])) {
      const changed = structuredClone(items) as Record<string, unknown>[];
      changed[index][key] = changed[index][key] === null ? 0 : null;
      assertThrows(() => matchPreparedVideoCohortItems(changed, input));
      delete changed[index][key];
      assertThrows(() => matchPreparedVideoCohortItems(changed, input));
    }
  }
  const changed = structuredClone(input);
  changed.evidence_manifest.provenance.source.sha256 = "f".repeat(64);
  assertThrows(() => matchPreparedVideoCohortItems(items, changed));
});

Deno.test("held video inventory preserves full graph validation and never accepts old inputs", () => {
  for (const value of [null, {}, { ...inputs[0].input, schema_version: 3 }]) {
    assertThrows(() => preparedVideoCohortItems(value));
  }
  const input = structuredClone(inputs[0].input);
  input.evidence_manifest.provenance.frames.reverse();
  assertThrows(() => preparedVideoCohortItems(input));
  const bad = structuredClone(inputs[0].input);
  bad.evidence_manifest.descriptions = ["a\u0000b"];
  assertThrows(() => preparedVideoCohortItems(bad));
});
