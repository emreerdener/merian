import { assertEquals } from "@std/assert";
import { projectDiscoveryScan } from "./db.ts";

Deno.test("discovery projection strips private review history and rejected species", () => {
  const source = {
    id: "00000000-0000-4000-8000-000000000001",
    ai_confidence_score: 0.9,
    gps_lat_public: 0,
    gps_long_public: 0,
    species_dictionary: { scientific_name: "Quercus alba" },
    ai_identification_review: {
      version: 1,
      revision: 1,
      state: "ai_rejected",
      origin_scan_id: "00000000-0000-4000-8000-000000000001",
      origin_identification: null,
      operation_id: "00000000-0000-4000-8000-000000000002",
      operation_digest: null,
      community: null,
    },
  };
  assertEquals(projectDiscoveryScan(source), { id: source.id });
  assertEquals(source.species_dictionary.scientific_name, "Quercus alba");
  assertEquals(
    projectDiscoveryScan({ ...source, ai_identification_review: null }),
    {
      id: source.id,
      ai_confidence_score: 0.9,
      gps_lat_public: 0,
      gps_long_public: 0,
      species_dictionary: { scientific_name: "Quercus alba" },
    },
  );
});
