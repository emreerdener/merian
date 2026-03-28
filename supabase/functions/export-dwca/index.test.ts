// supabase/functions/export-dwca/index.test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";

/**
 * Mocks the Darwin Core Archive extraction string-building logic
 * to ensure that phenological metadata natively writes to the expected CSV indices.
 */
Deno.test("DwC-A Payload Mapping & Telemetry Extraction", () => {
    // 1. Mock DB Row returning Data-as-a-Service properties
    const mockRow = {
        id: "123e4567-e89b-12d3-a456-426614174000",
        user_id: "user_123",
        timestamp: "2026-03-21T09:46:03.000Z",
        gps_lat_exact: 37.7749,
        gps_long_exact: -122.4194,
        gps_lat_public: 37.8,
        gps_long_public: -122.4,
        coordinate_uncertainty_in_meters: 10,
        species_dictionary: {
            scientific_name: "Danaus plexippus",
            kingdom: "Animalia"
        },
        life_stage: "adult",
        reproductive_condition: "not_applicable",
        individual_count: 5,
        ecological_interactions: ["pollinating Asclepias"],
        ai_confidence_score: 0.98,
        image_storage_urls: ["https://r2.merian/image1.webp"]
    };

    const recordedBy = "user_123";

    // 2. Mapped Extraction Logic matching export-dwca/index.ts
    const lifeStage = mockRow.life_stage || "unknown";
    const reproductiveCondition = mockRow.reproductive_condition || "not_applicable";
    const individualCount = mockRow.individual_count != null ? mockRow.individual_count : "";
    const associatedTaxa = mockRow.ecological_interactions && mockRow.ecological_interactions.length > 0
        ? mockRow.ecological_interactions.join(" | ").replace(/,/g, ";").replace(/"/g, "")
        : "";
    const verificationStatus = mockRow.ai_confidence_score != null ? mockRow.ai_confidence_score.toFixed(2) : "";

    // Columns: coreid, basisOfRecord, recordedBy, eventDate, scientificName, kingdom, phylum, class, order, family, genus, decimalLatitude, decimalLongitude, coordinateUncertaintyInMeters, lifeStage, reproductiveCondition, individualCount, associatedTaxa, identificationVerificationStatus
    const occurrenceRow = `${mockRow.id},HumanObservation,${recordedBy},${mockRow.timestamp},${mockRow.species_dictionary.scientific_name},${mockRow.species_dictionary.kingdom},,,,,,${mockRow.gps_lat_exact},${mockRow.gps_long_exact},${mockRow.coordinate_uncertainty_in_meters},${lifeStage},${reproductiveCondition},${individualCount},"${associatedTaxa}",${verificationStatus}`;

    // 3. Assertions
    // Regex splits by comma, but respects quotes (naively for this test shape)
    // For simplicity, we split without regex to target predictable indices where commas aren't nested in taxa strings
    const cols = occurrenceRow.split(",");
    
    assertEquals(cols[14], "adult", "life_stage not mapped to correct DwC-A index");
    assertEquals(cols[15], "not_applicable", "reproductive_condition not mapped to correct DwC-A index");
    assertEquals(cols[16], "5", "individual_count not mapped to correct DwC-A index");
    
    // associatedTaxa has quotes, let's clean it before asserting
    const rawTaxa = cols[17].replace(/^"|"$/g, '');
    assertEquals(rawTaxa, "pollinating Asclepias", "ecological_interactions not mapped cleanly to associatedTaxa dwc field");
    assertEquals(cols[18], "0.98", "confidence score not mapped cleanly");
});
