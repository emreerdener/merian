import { assert, assertEquals, assertThrows } from "@std/assert";
import retained from "./fixtures/retainedResultV1.json" with { type: "json" };
import { decodeInitialResult } from "./resultEvidence.ts";
import { dataContractV1 } from "./resultSchemaV1.ts";
import { parseInitialResultDataV1 } from "./resultSemanticsV1.ts";
import { transformInitialResult } from "./resultEncoding.ts";
import { parseIdentifySuccessEnvelope } from "../identify/contract.ts";

Deno.test("frozen v1 result recovers exact data and original hashes independently of current capture", async () => {
  const evidence = retained.evidence;
  const recovered = await decodeInitialResult(
    evidence,
    evidence.reference,
    evidence.provenance_canonical,
  );
  assertEquals<unknown>(recovered, retained.data);
  assert(Object.isFrozen(recovered));
  assert(
    Object.isFrozen(dataContractV1.fields.identification_provenance.contract),
  );
});
function primary(resolution = "species") {
  const d = structuredClone(retained.data);
  return {
    ...d,
    identification_provenance: {
      ...d.identification_provenance,
      schema: "merian_identify_primary_v1",
    },
    primary_identification: {
      version: 1,
      resolution,
      scientific_name: d.scientific_name,
      common_name: d.common_name,
    },
    candidates: resolution === "species"
      ? d.candidates.map((c) => ({ ...c, taxon_rank: "species" }))
      : null,
    pet_identification: null,
    is_new_to_merian_dictionary: false,
  };
}
for (const resolution of ["species", "genus", "family"]) {
  Deno.test(`pinned primary ${resolution} semantic vector matches original public behavior`, () => {
    const d = primary(resolution);
    assertEquals(
      parseInitialResultDataV1(d),
      parseIdentifySuccessEnvelope({ success: true, data: d }).data,
    );
  });
}
for (const resolution of ["unresolved_biological", "non_biological"]) {
  Deno.test(`pinned primary ${resolution} preserves required null identity`, () => {
    const d = {
      ...primary(resolution),
      scientific_name: null,
      common_name: null,
      is_biological_subject: resolution !== "non_biological",
      primary_identification: {
        version: 1,
        resolution,
        scientific_name: null,
        common_name: null,
      },
    };
    assertEquals(
      parseInitialResultDataV1(d),
      parseIdentifySuccessEnvelope({ success: true, data: d }).data,
    );
    assertThrows(() =>
      parseInitialResultDataV1({
        ...d,
        primary_identification: {
          ...d.primary_identification,
          scientific_name: "Unexpected",
        },
      })
    );
  });
}
for (
  const mode of [
    "missing",
    "legacy_with_primary",
    "identity",
    "subject",
    "rank",
    "alternatives",
    "non_species_effect",
    "enrichment",
    "family_genus",
    "unsanitized",
  ]
) {
  Deno.test(`pinned primary rejects ${mode}`, () => {
    const d: Record<string, unknown> = primary();
    if (mode === "missing") delete d.primary_identification;
    if (mode === "legacy_with_primary") {
      d.identification_provenance = retained.data.identification_provenance;
    }
    if (mode === "identity") d.common_name = "Different";
    if (mode === "subject") d.is_biological_subject = false;
    if (mode === "rank") d.candidates = retained.data.candidates;
    if (mode === "alternatives") {
      d.candidates = Array(3).fill(primary().candidates![0]);
    }
    if (mode === "non_species_effect") {
      Object.assign(d, primary("genus"), {
        candidates: retained.data.candidates,
      });
    }
    if (mode === "enrichment") {
      Object.assign(d, primary("genus"), {
        wikipedia_url: "https://example.com",
      });
    }
    if (mode === "family_genus") {
      Object.assign(d, primary("family"), { taxonomy: { genus: "Danaus" } });
    }
    if (mode === "unsanitized") {
      d.primary_identification = {
        ...primary().primary_identification,
        scientific_name: " Danaus plexippus",
      };
    }
    assertThrows(() => parseInitialResultDataV1(d));
    assertThrows(() =>
      parseIdentifySuccessEnvelope({ success: true, data: d })
    );
  });
}
Deno.test("pinned scalar and object rules preserve omission/null/Unicode/numbers and reject expansion", () => {
  const d = structuredClone(retained.data);
  assertEquals(parseInitialResultDataV1(d).pet_identification, null);
  assert(!Object.hasOwn(parseInitialResultDataV1(d), "taxonomy"));
  assertThrows(() => parseInitialResultDataV1({ ...d, extra: "future field" }));
  for (const value of [-0, Infinity, NaN, 1.1]) {
    assertThrows(() =>
      parseInitialResultDataV1({ ...d, confidence_score: value })
    );
  }
  for (const value of ["\ud800", "\u0000", "a".repeat(256)]) {
    assertThrows(() => parseInitialResultDataV1({ ...d, common_name: value }));
  }
  assertEquals(
    parseInitialResultDataV1({ ...d, common_name: "🦋" }).common_name,
    "🦋",
  );
  assertThrows(() =>
    transformInitialResult(
      dataContractV1,
      { ...d, confidence_score: "0.870" },
      "decode",
    )
  );
});
