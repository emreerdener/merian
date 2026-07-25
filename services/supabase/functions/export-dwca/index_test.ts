import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
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
