import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { generateDwcARow } from "./dwca.ts";

const mockSalt = "testSalt123";

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

  // Act
  const result = await generateDwcARow(
    // @ts-ignore: mock test object cast
    scan,
    "global", // Forces anonymization
    false,
    "emre_uuid_0001",
    mockSalt
  );

  // Assert
  // Instead of 'emre_uuid_0001', it should output 'merian_user_...'
  const parts = result.occurrenceRow.split(",");
  const recordedBy = parts[2];
  
  assertEquals(recordedBy.startsWith("merian_user_"), true);
  assertEquals(recordedBy.includes("emre_uuid_0001"), false);
});

Deno.test("generateDwcARow does not mask UUID on personal exports", async () => {
    const scan = {
      id: "scan_124",
      user_id: "emre_uuid_0001"
    };
  
    const result = await generateDwcARow(
      // @ts-ignore: mock test object cast
      scan,
      "personal",
      false,
      "emre_uuid_0001",
      mockSalt
    );
  
    const parts = result.occurrenceRow.split(",");
    assertEquals(parts[2], "emre_uuid_0001");
});

Deno.test("generateDwcARow truncates precision on protected species", async () => {
    const scan = {
      id: "scan_125",
      user_id: "emre_uuid_0001",
      gps_lat_exact: 40.71285901,
      gps_long_exact: -74.00601243,
      gps_lat_public: 40.7,
      gps_long_public: -74.0,
      species_dictionary: {
        scientific_name: "Ailuropoda melanoleuca",
        iucn_red_list_status: "vulnerable" // Should trigger protection
      }
    };
  
    // Act
    const result = await generateDwcARow(
      // @ts-ignore: mock test object cast
      scan,
      "personal",
      true, // Requesting exact coordinates, but species is protected!
      "emre_uuid_0001",
      mockSalt
    );
  
    const parts = result.occurrenceRow.split(",");
    const lat = parts[11];
    const lon = parts[12];
    
    // Protection math rounds to nearest tenth (Math.round(lat * 10) / 10)
    assertEquals(lat, "40.7");
    assertEquals(lon, "-74"); // -74.006 shrinks to -74
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
      scan,
      "personal",
      true, 
      "emre_uuid_0001",
      mockSalt
    );
  
    const parts = result.occurrenceRow.split(",");
    const lat = parts[11];
    const lon = parts[12];
    
    assertEquals(lat, "40.71285901");
    assertEquals(lon, "-74.00601243");
});
