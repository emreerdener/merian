import { assert, assertEquals } from "@std/assert";
import { generateDwcARow } from "./dwca.ts";
import { createUserPseudonymizer } from "./pseudonym.ts";

const pseudonymizer = await createUserPseudonymizer(
  1,
  btoa("0123456789abcdef0123456789abcdef"),
);

function unquote(field: string): string {
  return field.replace(/^"|"$/g, "").replace(/""/g, '"');
}

function splitCsvRow(row: string): string[] {
  const fields: string[] = [];
  let current = "";
  let inQuotes = false;
  for (let index = 0; index < row.length; index += 1) {
    const character = row[index];
    if (character === '"') {
      if (inQuotes && row[index + 1] === '"') {
        current += '"';
        index += 1;
      } else {
        inQuotes = !inQuotes;
        current += character;
      }
    } else if (character === "," && !inQuotes) {
      fields.push(current);
      current = "";
    } else {
      current += character;
    }
  }
  fields.push(current);
  return fields;
}

Deno.test("global DwC-A rows use versioned HMAC pseudonyms", async () => {
  const result = await generateDwcARow(
    {
      id: "scan_123",
      user_id: "00000000-0000-4000-8000-000000000401",
      timestamp: "2026-03-28T12:00:00Z",
      gps_lat_public: 40.7128,
      gps_long_public: -74.006,
      species_dictionary: {
        scientific_name: "Turdus migratorius",
        kingdom: "Animalia",
      },
    },
    "global",
    false,
    "00000000-0000-4000-8000-000000000401",
    pseudonymizer,
  );

  const recordedBy = splitCsvRow(result.occurrenceRow).map(unquote)[2];
  assertEquals(
    recordedBy,
    await pseudonymizer.pseudonymize(
      "00000000-0000-4000-8000-000000000401",
    ),
  );
  assertEquals(recordedBy.includes("00000000"), false);
});

Deno.test("personal DwC-A rows retain the requesting user's UUID", async () => {
  const userId = "00000000-0000-4000-8000-000000000402";
  const result = await generateDwcARow(
    { id: "scan_124", user_id: userId },
    "personal",
    false,
    userId,
    null,
  );
  assertEquals(splitCsvRow(result.occurrenceRow).map(unquote)[2], userId);
});

Deno.test("ownerless tombstones retain no linkable recorder", async () => {
  const result = await generateDwcARow(
    {
      id: "scan_ownerless_tombstone",
      user_id: null,
      gps_lat_exact: 41.881832,
      gps_long_exact: -87.623177,
      gps_lat_public: 41.8,
      gps_long_public: -87.6,
    },
    "global",
    true,
    "00000000-0000-4000-8000-000000000402",
    null,
  );
  const fields = splitCsvRow(result.occurrenceRow).map(unquote);
  assertEquals(fields[2], "Naturebook Citizen Scientist");
  assertEquals(fields[11], "41.8");
  assertEquals(fields[12], "-87.6");
});

Deno.test("protected species always use coarse public coordinates", async () => {
  const userId = "00000000-0000-4000-8000-000000000403";
  const result = await generateDwcARow(
    {
      id: "scan_125",
      user_id: userId,
      gps_lat_exact: 40.85,
      gps_long_exact: -74.36,
      gps_lat_public: 40,
      gps_long_public: -74,
      species_dictionary: {
        scientific_name: "Ailuropoda melanoleuca",
        iucn_red_list_status: "vulnerable",
      },
    },
    "personal",
    true,
    userId,
    null,
  );
  const fields = splitCsvRow(result.occurrenceRow).map(unquote);
  assertEquals(fields[11], "40");
  assertEquals(fields[12], "-74");
});

Deno.test("personal non-protected rows honor requested precision", async () => {
  const userId = "00000000-0000-4000-8000-000000000404";
  const result = await generateDwcARow(
    {
      id: "scan_126",
      user_id: userId,
      gps_lat_exact: 40.71285901,
      gps_long_exact: -74.00601243,
      species_dictionary: {
        scientific_name: "Columba livia",
        iucn_red_list_status: "least_concern",
      },
    },
    "personal",
    true,
    userId,
    null,
  );
  const fields = splitCsvRow(result.occurrenceRow).map(unquote);
  assertEquals(fields[11], "40.71285901");
  assertEquals(fields[12], "-74.00601243");
});

Deno.test("DwC-A rows preserve RFC 4180 field boundaries", async () => {
  const result = await generateDwcARow(
    {
      id: "scan_127",
      user_id: "00000000-0000-4000-8000-000000000405",
      sex: "female",
      ecological_interactions: [
        'eats "aphids", beetles',
        "parasitized by Cotesia glomerata",
      ],
      species_dictionary: { scientific_name: "Papilio, sp." },
    },
    "personal",
    false,
    "00000000-0000-4000-8000-000000000405",
    null,
  );

  const fields = splitCsvRow(result.occurrenceRow);
  assertEquals(fields.length, 20);
  assertEquals(unquote(fields[4]), "Papilio, sp.");
  assertEquals(unquote(fields[17]), "female");
});

Deno.test("null taxonomy rows remain exportable", async () => {
  const result = await generateDwcARow(
    {
      id: "scan_null_dict",
      user_id: "00000000-0000-4000-8000-000000000406",
      species_dictionary: null,
    },
    "personal",
    false,
    "00000000-0000-4000-8000-000000000406",
    null,
  );
  const scientificName = splitCsvRow(result.occurrenceRow).map(unquote)[4];
  assertEquals(scientificName, "");
  assert(!result.occurrenceRow.includes("undefined"));
});

Deno.test("DwC-A renders frozen confidence only when its snapshot qualifies or predates the flag", async () => {
  const userId = "00000000-0000-4000-8000-000000000402";
  for (const scope of ["personal", "global"] as const) {
    for (const qualified of [undefined, true, false]) {
      const result = await generateDwcARow(
        {
          id: "synthetic-metric-scan",
          user_id: userId,
          ai_confidence_score: 0.987,
          ...(qualified === undefined
            ? {}
            : { ai_confidence_qualified: qualified }),
        },
        scope,
        false,
        userId,
        pseudonymizer,
      );
      const fields = splitCsvRow(result.occurrenceRow).map(unquote);
      assertEquals(fields[19], qualified === false ? "" : "0.99");
      assertEquals(fields[0], "synthetic-metric-scan");
      assertEquals(fields.length, 20);
      assertEquals(result.occurrenceRow.includes("qualified"), false);
    }
  }
});

Deno.test("DwC-A freezes broader rank and separates verified selection from AI confidence", async () => {
  for (
    const rank of [
      "species",
      "genus",
      "family",
      "unresolved_biological",
    ] as const
  ) {
    const row = await generateDwcARow(
      {
        id: "rank-fixture",
        user_id: null,
        species_dictionary: null,
        ai_confidence_score: 0.99,
        ai_confidence_qualified: false,
        identification: {
          rank,
          scientific_name: rank === "unresolved_biological"
            ? null
            : "Fixtureus",
          verified_selection: rank === "species",
        },
      },
      "personal",
      false,
      "fixture-owner",
      null,
    );
    const fields = splitCsvRow(row.occurrenceRow).map(unquote);
    assertEquals(
      fields[4],
      rank === "unresolved_biological" ? "" : "Fixtureus",
    );
    assertEquals(fields.length, 20);
    assertEquals(
      fields[19],
      rank === "species"
        ? "Observer-selected species; taxonomy verified"
        : `AI identification rank: ${rank}`,
    );
  }
});
