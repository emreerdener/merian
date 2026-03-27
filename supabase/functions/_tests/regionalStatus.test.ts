import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  locationMatchesRegion,
  calculateRegionalStatus,
} from "../_shared/regionalStatus.ts";

// ---------------------------------------------------------------------------
// locationMatchesRegion — country-level matching
// ---------------------------------------------------------------------------

Deno.test("locationMatchesRegion — matches ISO code directly in location string", () => {
  assertEquals(locationMatchesRegion("PARIS, FR", "FR"), true);
});

Deno.test("locationMatchesRegion — matches country alias (full name)", () => {
  assertEquals(locationMatchesRegion("NEW YORK, UNITED STATES", "US"), true);
});

Deno.test("locationMatchesRegion — matches 'USA' alias", () => {
  assertEquals(locationMatchesRegion("AUSTIN, USA", "US"), true);
});

Deno.test("locationMatchesRegion — case-insensitive (loc must be uppercased by caller)", () => {
  // The function expects an already-uppercased loc; verify it works with uppercase
  assertEquals(locationMatchesRegion("AUSTIN, TEXAS, UNITED STATES", "US"), true);
});

Deno.test("locationMatchesRegion — returns false for unrelated country", () => {
  assertEquals(locationMatchesRegion("SYDNEY, AUSTRALIA", "US"), false);
});

// ---------------------------------------------------------------------------
// locationMatchesRegion — token boundary safety (prevents false positives)
// ---------------------------------------------------------------------------

Deno.test("locationMatchesRegion — 'IN' code does not match 'INDIANA'", () => {
  // "IN" (India) should not match "Austin, Indiana, United States"
  assertEquals(locationMatchesRegion("AUSTIN, INDIANA, UNITED STATES", "IN"), false);
});

Deno.test("locationMatchesRegion — 'IN' code matches India alias", () => {
  assertEquals(locationMatchesRegion("MUMBAI, INDIA", "IN"), true);
});

Deno.test("locationMatchesRegion — 'ID' code does not match 'IDAHO'", () => {
  // "ID" (Indonesia) should not match "Boise, Idaho, United States"
  assertEquals(locationMatchesRegion("BOISE, IDAHO, UNITED STATES", "ID"), false);
});

// ---------------------------------------------------------------------------
// locationMatchesRegion — US sub-region (state) matching
// ---------------------------------------------------------------------------

Deno.test("locationMatchesRegion — matches US-TX via abbreviated code", () => {
  assertEquals(locationMatchesRegion("AUSTIN, TX, UNITED STATES", "US-TX"), true);
});

Deno.test("locationMatchesRegion — matches US-TX via full state name (CLGeocoder format)", () => {
  assertEquals(locationMatchesRegion("AUSTIN, TEXAS, UNITED STATES", "US-TX"), true);
});

Deno.test("locationMatchesRegion — does not match different US state", () => {
  assertEquals(locationMatchesRegion("AUSTIN, TEXAS, UNITED STATES", "US-CA"), false);
});

Deno.test("locationMatchesRegion — matches US-NY via full state name", () => {
  assertEquals(locationMatchesRegion("NEW YORK CITY, NEW YORK, UNITED STATES", "US-NY"), true);
});

Deno.test("locationMatchesRegion — matches US-DC", () => {
  assertEquals(locationMatchesRegion("WASHINGTON, DISTRICT OF COLUMBIA, UNITED STATES", "US-DC"), true);
});

Deno.test("locationMatchesRegion — US country code alone matches any US location", () => {
  assertEquals(locationMatchesRegion("AUSTIN, TEXAS, UNITED STATES", "US"), true);
});

// ---------------------------------------------------------------------------
// locationMatchesRegion — non-US countries without sub-regions
// ---------------------------------------------------------------------------

Deno.test("locationMatchesRegion — matches GB via 'UNITED KINGDOM' alias", () => {
  assertEquals(locationMatchesRegion("LONDON, UNITED KINGDOM", "GB"), true);
});

Deno.test("locationMatchesRegion — matches GB via 'ENGLAND' alias", () => {
  assertEquals(locationMatchesRegion("LONDON, ENGLAND", "GB"), true);
});

Deno.test("locationMatchesRegion — matches AU via 'AUSTRALIA' alias", () => {
  assertEquals(locationMatchesRegion("SYDNEY, AUSTRALIA", "AU"), true);
});

// ---------------------------------------------------------------------------
// locationMatchesRegion — edge cases
// ---------------------------------------------------------------------------

Deno.test("locationMatchesRegion — empty location string returns false", () => {
  assertEquals(locationMatchesRegion("", "US"), false);
});

Deno.test("locationMatchesRegion — location equals country code exactly", () => {
  assertEquals(locationMatchesRegion("FR", "FR"), true);
});

// ---------------------------------------------------------------------------
// calculateRegionalStatus — invasive species
// ---------------------------------------------------------------------------

Deno.test("calculateRegionalStatus — invasive flag overrides everything", () => {
  const result = calculateRegionalStatus("Austin, Texas, United States", true, ["US-TX"]);
  assertEquals(result, "Regarded as an invasive species in this region.");
});

Deno.test("calculateRegionalStatus — invasive with null location", () => {
  const result = calculateRegionalStatus(null, true, null);
  assertEquals(result, "Regarded as an invasive species in this region.");
});

// ---------------------------------------------------------------------------
// calculateRegionalStatus — no region data
// ---------------------------------------------------------------------------

Deno.test("calculateRegionalStatus — null regions returns unverified", () => {
  const result = calculateRegionalStatus("Austin, Texas, United States", false, null);
  assertEquals(result, "Global distribution unverified.");
});

Deno.test("calculateRegionalStatus — empty regions array returns unverified", () => {
  const result = calculateRegionalStatus("Austin, Texas, United States", false, []);
  assertEquals(result, "Global distribution unverified.");
});

// ---------------------------------------------------------------------------
// calculateRegionalStatus — native detection
// ---------------------------------------------------------------------------

Deno.test("calculateRegionalStatus — native match via CLGeocoder full-name format", () => {
  const result = calculateRegionalStatus(
    "Austin, Texas, United States",
    false,
    ["US-TX", "MX"]
  );
  assertEquals(result, "Native to this region based on exact spatial distribution bounds.");
});

Deno.test("calculateRegionalStatus — native match via abbreviated code format", () => {
  const result = calculateRegionalStatus(
    "AUSTIN, TX, UNITED STATES",
    false,
    ["US-TX"]
  );
  assertEquals(result, "Native to this region based on exact spatial distribution bounds.");
});

Deno.test("calculateRegionalStatus — non-native when location outside regions", () => {
  const result = calculateRegionalStatus(
    "London, England",
    false,
    ["US-TX", "MX"]
  );
  assertEquals(result, "Introduced or unverified native presence in this exact capturing area.");
});

Deno.test("calculateRegionalStatus — native match with country-level region code", () => {
  const result = calculateRegionalStatus(
    "Paris, France",
    false,
    ["FR", "DE"]
  );
  assertEquals(result, "Native to this region based on exact spatial distribution bounds.");
});

Deno.test("calculateRegionalStatus — null location with valid regions is non-native", () => {
  const result = calculateRegionalStatus(null, false, ["US-TX"]);
  assertEquals(result, "Introduced or unverified native presence in this exact capturing area.");
});
