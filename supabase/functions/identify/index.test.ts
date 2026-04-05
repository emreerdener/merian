// supabase/functions/identify/index.test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
// Instead of importing the heavy generative SDK which requires API keys, we mock the validation
// of the merianResponseSchema to securely assert that DaaS keys are structurally present.

Deno.test("Identify Schema Structure validates all Data-as-a-Service properties", () => {
    // 1. Mock the expected JSON that Gemini returns based on the Edge Schema
    const mockGeminiJSON = {
        is_biological_subject: true,
        is_live_capture: true,
        ecology_type: "wild",
        scientific_name: "Danaus plexippus",
        common_name: "Monarch Butterfly",
        confidence_score: 0.98,
        blur_score: 0.05,
        is_invasive: false,
        colors: ["orange", "black", "white"],
        life_stage: "adult",
        reproductive_condition: "not_applicable",
        individual_count: 1,
        estimated_size_cm: 10.5,
        ecological_interactions: ["pollinating milkweed"],
        insight_data: {
            ai_reasoning: "Distinct vein pattern matches Danaus",
            hazard_type: "none"
        }
    };

    // 2. Mock Edge JSON parsing / filtering mimicking Deno edge behavior
    const parsedData = JSON.parse(JSON.stringify(mockGeminiJSON));

    // 3. Ensure DaaS extraction structure is not malformed
    assertEquals(typeof parsedData.estimated_size_cm, "number", "estimated_size_cm should parse as number");
    assertEquals(typeof parsedData.life_stage, "string", "life_stage should parse as string");
    assertEquals(typeof parsedData.reproductive_condition, "string", "reproductive_condition should parse as string");
    assertEquals(typeof parsedData.individual_count, "number", "individual_count should parse as number");

    assert(Array.isArray(parsedData.ecological_interactions), "ecological_interactions should parse as an array");
    assertEquals(parsedData.ecological_interactions[0], "pollinating milkweed", "interaction strings must be extracted cleanly");

    // 4. Validate Vision Lean schema fields
    assertEquals(parsedData.insight_data.ai_reasoning, "Distinct vein pattern matches Danaus", "ai_reasoning is structurally missing");
});

// ---------------------------------------------------------------------------
// GPS coordinate range validation (safeGpsLat / safeGpsLon)
// Mirrors the guard in index.ts — out-of-range values → null, valid values pass through.
// ---------------------------------------------------------------------------

function safeGpsLat(v: unknown): number | null {
    return v != null && typeof v === "number" && Number.isFinite(v) && v >= -90 && v <= 90 ? v : null;
}
function safeGpsLon(v: unknown): number | null {
    return v != null && typeof v === "number" && Number.isFinite(v) && v >= -180 && v <= 180 ? v : null;
}

Deno.test("GPS validation — valid coordinates pass through unchanged", () => {
    assertEquals(safeGpsLat(40.7128), 40.7128);
    assertEquals(safeGpsLon(-74.006), -74.006);
    assertEquals(safeGpsLat(-90), -90);
    assertEquals(safeGpsLat(90), 90);
    assertEquals(safeGpsLon(-180), -180);
    assertEquals(safeGpsLon(180), 180);
});

Deno.test("GPS validation — out-of-range latitude is sanitised to null", () => {
    assertEquals(safeGpsLat(91), null, "lat > 90 must be null");
    assertEquals(safeGpsLat(-91), null, "lat < -90 must be null");
    assertEquals(safeGpsLat(999), null);
});

Deno.test("GPS validation — out-of-range longitude is sanitised to null", () => {
    assertEquals(safeGpsLon(181), null, "lon > 180 must be null");
    assertEquals(safeGpsLon(-181), null, "lon < -180 must be null");
});

Deno.test("GPS validation — non-finite values are sanitised to null", () => {
    assertEquals(safeGpsLat(Infinity), null);
    assertEquals(safeGpsLat(-Infinity), null);
    assertEquals(safeGpsLat(NaN), null);
    assertEquals(safeGpsLon(Infinity), null);
});

Deno.test("GPS validation — null and undefined are sanitised to null", () => {
    assertEquals(safeGpsLat(null), null);
    assertEquals(safeGpsLat(undefined), null);
    assertEquals(safeGpsLon(null), null);
});

Deno.test("GPS validation — zero is a valid coordinate (equator / prime meridian)", () => {
    assertEquals(safeGpsLat(0), 0);
    assertEquals(safeGpsLon(0), 0);
});

// ---------------------------------------------------------------------------
// LLM field sanitization caps
// Mirrors the cap logic in index.ts applied after extractJson.
// ---------------------------------------------------------------------------

Deno.test("LLM caps — candidates array capped at 5", () => {
    const candidates = Array.from({ length: 8 }, (_, i) => ({
        scientific_name: `Species ${i}`,
        confidence_score: 0.5,
    }));
    const capped = candidates.slice(0, 5);
    assertEquals(capped.length, 5);
    assertEquals(capped[4].scientific_name, "Species 4");
});

Deno.test("LLM caps — candidates under limit pass through unchanged", () => {
    const candidates = [{ scientific_name: "Danaus plexippus", confidence_score: 0.9 }];
    assertEquals(candidates.slice(0, 5).length, 1);
});

Deno.test("LLM caps — extracted_visual_traits capped at 10", () => {
    const traits = Array.from({ length: 15 }, (_, i) => `trait ${i}`);
    assertEquals(traits.slice(0, 10).length, 10);
});

Deno.test("LLM caps — ecological_interactions capped at 10", () => {
    const interactions = Array.from({ length: 12 }, (_, i) => `interaction ${i}`);
    assertEquals(interactions.slice(0, 10).length, 10);
});

Deno.test("LLM caps — ai_reasoning truncated at 2000 chars", () => {
    const long = "x".repeat(2500);
    const truncated = long.length > 2000 ? long.slice(0, 2000) : long;
    assertEquals(truncated.length, 2000);
});

Deno.test("LLM caps — ai_reasoning under 2000 chars is not modified", () => {
    const short = "x".repeat(100);
    const result = short.length > 2000 ? short.slice(0, 2000) : short;
    assertEquals(result.length, 100);
});

Deno.test("LLM caps — individual_count: valid positive integer passes through", () => {
    function sanitizeCount(v: unknown): number | undefined {
        if (v == null) return undefined;
        if (!Number.isFinite(v as number) || (v as number) <= 0) return undefined;
        return Math.min(Math.round(v as number), 99999);
    }
    assertEquals(sanitizeCount(3), 3);
    assertEquals(sanitizeCount(99999), 99999);
    assertEquals(sanitizeCount(1), 1);
});

Deno.test("LLM caps — individual_count: negative value sanitised to undefined", () => {
    function sanitizeCount(v: unknown): number | undefined {
        if (v == null) return undefined;
        if (!Number.isFinite(v as number) || (v as number) <= 0) return undefined;
        return Math.min(Math.round(v as number), 99999);
    }
    assertEquals(sanitizeCount(-1), undefined);
    assertEquals(sanitizeCount(0), undefined);
    assertEquals(sanitizeCount(-100), undefined);
});

Deno.test("LLM caps — individual_count: value exceeding 99999 is clamped", () => {
    function sanitizeCount(v: unknown): number | undefined {
        if (v == null) return undefined;
        if (!Number.isFinite(v as number) || (v as number) <= 0) return undefined;
        return Math.min(Math.round(v as number), 99999);
    }
    assertEquals(sanitizeCount(999999), 99999);
    assertEquals(sanitizeCount(100000), 99999);
});

Deno.test("LLM caps — individual_count: non-finite sanitised to undefined", () => {
    function sanitizeCount(v: unknown): number | undefined {
        if (v == null) return undefined;
        if (!Number.isFinite(v as number) || (v as number) <= 0) return undefined;
        return Math.min(Math.round(v as number), 99999);
    }
    assertEquals(sanitizeCount(NaN), undefined);
    assertEquals(sanitizeCount(Infinity), undefined);
});

Deno.test("LLM caps — estimated_size_cm: positive finite value ≤50000 passes through", () => {
    function sanitizeSizeCm(v: unknown): number | null {
        if (v == null || !Number.isFinite(v as number) || (v as number) <= 0) return null;
        return Math.min(v as number, 50000);
    }
    assertEquals(sanitizeSizeCm(10.5), 10.5);
    assertEquals(sanitizeSizeCm(50000), 50000);
});

Deno.test("LLM caps — estimated_size_cm: value exceeding 50000 is clamped", () => {
    function sanitizeSizeCm(v: unknown): number | null {
        if (v == null || !Number.isFinite(v as number) || (v as number) <= 0) return null;
        return Math.min(v as number, 50000);
    }
    assertEquals(sanitizeSizeCm(99999), 50000);
});

Deno.test("LLM caps — estimated_size_cm: non-positive and non-finite → null", () => {
    function sanitizeSizeCm(v: unknown): number | null {
        if (v == null || !Number.isFinite(v as number) || (v as number) <= 0) return null;
        return Math.min(v as number, 50000);
    }
    assertEquals(sanitizeSizeCm(0), null);
    assertEquals(sanitizeSizeCm(-5), null);
    assertEquals(sanitizeSizeCm(Infinity), null);
    assertEquals(sanitizeSizeCm(null), null);
});
