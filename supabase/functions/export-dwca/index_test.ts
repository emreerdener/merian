import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { generateDwcARow } from "./dwca.ts";

const mockSalt = "testSalt123";

// All fields are RFC 4180 quoted — strip surrounding quotes before asserting values.
function unquote(field: string): string {
  return field.replace(/^"|"$/g, "").replace(/""/g, '"');
}

// Split a CSV row respecting quoted fields (commas inside quotes are not delimiters).
function splitCsvRow(row: string): string[] {
  const fields: string[] = [];
  let current = "";
  let inQuotes = false;
  for (let i = 0; i < row.length; i++) {
    const ch = row[i];
    if (ch === '"') {
      if (inQuotes && row[i + 1] === '"') { current += '"'; i++; }
      else { inQuotes = !inQuotes; current += ch; }
    } else if (ch === "," && !inQuotes) {
      fields.push(current); current = "";
    } else {
      current += ch;
    }
  }
  fields.push(current);
  return fields;
}

Deno.test("generateDwcARow masking UUID successfully on global exports", async () => {
  const scan = {
    id: "scan_123",
    user_id: "emre_uuid_0001",
    timestamp: "2026-03-28T12:00:00Z",
    gps_lat_public: 40.7128,
    gps_long_public: -74.0060,
    species_dictionary: {
      scientific_name: "Turdus migratorius",
      kingdom: "Animalia"
    }
  };

  const result = await generateDwcARow(
    // @ts-ignore: mock test object cast
    scan, "global", false, "emre_uuid_0001", mockSalt
  );

  const parts = splitCsvRow(result.occurrenceRow).map(unquote);
  const recordedBy = parts[2];

  assertEquals(recordedBy.startsWith("merian_user_"), true);
  assertEquals(recordedBy.includes("emre_uuid_0001"), false);
});

Deno.test("generateDwcARow does not mask UUID on personal exports", async () => {
  const scan = { id: "scan_124", user_id: "emre_uuid_0001" };

  const result = await generateDwcARow(
    // @ts-ignore: mock test object cast
    scan, "personal", false, "emre_uuid_0001", mockSalt
  );

  const parts = splitCsvRow(result.occurrenceRow).map(unquote);
  assertEquals(parts[2], "emre_uuid_0001");
});

// Exact coords deliberately chosen so that Math.round(exact * 10) / 10 produces
// a DIFFERENT value than the public coord. This ensures the test would FAIL if
// the protection logic erroneously used the exact coordinate instead of the
// public coordinate for a protected species.
//
//   gps_lat_exact  40.85  → rounds to 40.9  (≠ public 40.0)
//   gps_long_exact -74.36 → rounds to -74.4 (≠ public -74.0)
//
// Expected output must match the PUBLIC coordinates (already coarse) passed
// through Math.round, not the exact ones.
Deno.test("generateDwcARow uses public coordinates for protected species", async () => {
  const scan = {
    id: "scan_125",
    user_id: "emre_uuid_0001",
    gps_lat_exact: 40.85,
    gps_long_exact: -74.36,
    gps_lat_public: 40.0,
    gps_long_public: -74.0,
    species_dictionary: {
      scientific_name: "Ailuropoda melanoleuca",
      iucn_red_list_status: "vulnerable"
    }
  };

  const result = await generateDwcARow(
    // @ts-ignore: mock test object cast
    scan, "personal", true, "emre_uuid_0001", mockSalt
  );

  const parts = splitCsvRow(result.occurrenceRow).map(unquote);
  // Public coord 40.0 → Math.round(40.0 * 10) / 10 = 40.0 → "40"
  // If exact were used: Math.round(40.85 * 10) / 10 = 40.9 → test would fail.
  assertEquals(parts[11], "40");
  // Public coord -74.0 → Math.round(-74.0 * 10) / 10 = -74.0 → "-74"
  // If exact were used: Math.round(-74.36 * 10) / 10 = -74.4 → test would fail.
  assertEquals(parts[12], "-74");
});

Deno.test("generateDwcARow honors exact precision if species is not protected", async () => {
  const scan = {
    id: "scan_126",
    user_id: "emre_uuid_0001",
    gps_lat_exact: 40.71285901,
    gps_long_exact: -74.00601243,
    species_dictionary: {
      scientific_name: "Columba livia",
      iucn_red_list_status: "least_concern"
    }
  };

  const result = await generateDwcARow(
    // @ts-ignore: mock test object cast
    scan, "personal", true, "emre_uuid_0001", mockSalt
  );

  const parts = splitCsvRow(result.occurrenceRow).map(unquote);
  assertEquals(parts[11], "40.71285901");
  assertEquals(parts[12], "-74.00601243");
});

Deno.test("generateDwcARow escapes commas and quotes in free-text fields", async () => {
  const scan = {
    id: "scan_127",
    user_id: "emre_uuid_0001",
    ecological_interactions: ['eats "aphids", beetles', "parasitized by Cotesia glomerata"],
    species_dictionary: { scientific_name: "Papilio, sp." }
  };

  const result = await generateDwcARow(
    // @ts-ignore: mock test object cast
    scan, "personal", false, "emre_uuid_0001", mockSalt
  );

  // Row must parse to exactly 19 fields despite commas inside values.
  const parts = splitCsvRow(result.occurrenceRow);
  assertEquals(parts.length, 19);

  // scientificName field should contain the comma intact after unquoting.
  assertEquals(unquote(parts[4]), "Papilio, sp.");
});
