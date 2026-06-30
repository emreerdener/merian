import { assertEquals, assertNotEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { fetchExternalEnrichment } from "./external.ts";

Deno.test("fetchExternalEnrichment resolves disambiguation for Rosa to standard description", async () => {
  const result = await fetchExternalEnrichment("Rosa");
  
  assertNotEquals(result.wikipediaUrl, null);
  assertNotEquals(result.wikiExtract, null);
  
  // It should NOT contain "refer to" which is typical for a disambiguation page.
  assertEquals(result.wikiExtract?.includes("refer to"), false);
  
  // It should resolve to the plant/rose details.
  // Rosa (plant) redirects to Rose on Wikipedia
  assertEquals(result.wikiTitle, "Rose");
  assertEquals(result.wikiExtract?.includes("woody perennial flowering plant"), true);
});

Deno.test("fetchExternalEnrichment resolves standard non-disambiguation species correctly", async () => {
  const result = await fetchExternalEnrichment("Panthera leo");
  
  assertNotEquals(result.wikipediaUrl, null);
  assertNotEquals(result.wikiExtract, null);
  assertEquals(result.wikiTitle, "Lion");
  assertEquals(result.wikiExtract?.includes("large cat of the genus Panthera"), true);
});
