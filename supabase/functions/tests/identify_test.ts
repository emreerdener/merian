import {
  assertEquals,
  assertExists,
  assertObjectMatch,
} from "https://deno.land/std@0.192.0/testing/asserts.ts";

/**
 * Merian "Golden Dataset" QA Protocol
 * Validates the Gemini 1.5 Flash AI inference engine schema and constraints.
 *
 * Pre-Requisites:
 * 1. Local Supabase instance must be running (supabase start).
 * 2. GEMINI_API_KEY must be stored in the local edge environment.
 *
 * Run locally via: supabase functions test identify
 */

const LOCAL_FUNCTION_URL = "http://127.0.0.1:54321/functions/v1/identify";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// Helper function dispatching mocked payloads natively to the Edge
async function simulateIdentifyRequest(payload: any) {
  const response = await fetch(LOCAL_FUNCTION_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Edge Function returned ${response.status}: ${errorText}`);
  }

  return await response.json();
}

Deno.test({
  name: "Test Case 1: The Any Ecology Test (Domesticated)",
  async fn() {
    // Mock Payload: A hypothetical URI of a potted Monstera plant indoors.
    const mockPayload = {
      geminiFileUris: [
        "https://storage.googleapis.com/generativeai-downloads/images/monstera_indoor.jpg",
      ],
      gpsLatExact: 40.7128,
      gpsLongExact: -74.006, // NYC
      subjectDistanceInMeters: 1.5,
      currentMonth: "May",
      deviceLocale: "en_US",
    };

    const result = await simulateIdentifyRequest(mockPayload);

    // Assertions
    assertExists(result);
    assertEquals(result.is_biological_subject, true);
    assertEquals(result.ecology_type, "domesticated");
    assertEquals(result.is_invasive, false);
    assertExists(result.taxonomy.genus);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Test Case 2: The Bioregional Test (Invasive Species)",
  async fn() {
    // Mock Payload: A Bastard Cabbage (Rapistrum rugosum) in Austin, TX.
    const mockPayload = {
      geminiFileUris: [
        "https://storage.googleapis.com/generativeai-downloads/images/bastard_cabbage.jpg",
      ],
      gpsLatExact: 30.2672, // Austin, TX
      gpsLongExact: -97.7431,
      subjectDistanceInMeters: 2.0,
      currentMonth: "April",
      deviceLocale: "en_US",
    };

    const result = await simulateIdentifyRequest(mockPayload);

    // Assertions
    assertExists(result);
    assertEquals(result.is_biological_subject, true);
    assertEquals(result.ecology_type, "wild");
    assertEquals(result.is_invasive, true);

    // Validate the regional_status_rationale populated correctly explaining Texas invasiveness
    assertExists(result.insight_data.regional_status_rationale);
    assertEquals(
      result.insight_data.regional_status_rationale.length > 5,
      true,
    );
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Test Case 3: The Hallucination Test (Non-Biological / Screen)",
  async fn() {
    // Mock Payload: A digital screen showing a bird or a parked car.
    const mockPayload = {
      geminiFileUris: [
        "https://storage.googleapis.com/generativeai-downloads/images/car_parked.jpg",
      ],
      gpsLatExact: 34.0522,
      gpsLongExact: -118.2437,
      subjectDistanceInMeters: 5.0,
      currentMonth: "July",
      deviceLocale: "en_US",
    };

    const result = await simulateIdentifyRequest(mockPayload);

    // Assertions
    assertExists(result);
    // AI should evaluate inanimate objects explicitly evaluating to false
    // or identifying the screen bounds to fail the `is_live_capture` validation.
    const isInvalidCapture =
      result.is_biological_subject === false ||
      result.is_live_capture === false;
    assertEquals(isInvalidCapture, true);
  },
  sanitizeOps: false,
  sanitizeResources: false,
});

Deno.test({
  name: "Test Case 4: The Ambiguity Test (Low Confidence Diagnostics)",
  async fn() {
    // Mock Payload: A blurry/ambiguous brown moth.
    const mockPayload = {
      geminiFileUris: [
        "https://storage.googleapis.com/generativeai-downloads/images/blurry_moth.jpg",
      ],
      gpsLatExact: 47.6062,
      gpsLongExact: -122.3321,
      subjectDistanceInMeters: 0.5,
      currentMonth: "August",
      deviceLocale: "en_US",
    };

    const result = await simulateIdentifyRequest(mockPayload);

    // Assertions
    assertExists(result);

    // Ensure either the AI was ultra confident despite blur, or it triggered the fallback
    if (result.confidence_score < 0.85) {
      assertExists(result.diagnostic_comparison);
      // Validate the comparative objects exist (using the schema implemented in Phase 4)
      assertExists(result.diagnostic_comparison.similar_species);
      assertExists(result.diagnostic_comparison.distinguishing_features);
    } else {
      console.log(
        `AI returned high confidence score: ${result.confidence_score}. Skipping diagnostic assert.`,
      );
    }
  },
  sanitizeOps: false,
  sanitizeResources: false,
});
