import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { coalesceTaxonomyValue, hasUsableLookalikeTaxonomy, normalizeTaxonomyValue } from "./taxonomy.ts";

Deno.test("normalizeTaxonomyValue collapses placeholder strings to null", () => {
  assertEquals(normalizeTaxonomyValue(null), null);
  assertEquals(normalizeTaxonomyValue(""), null);
  assertEquals(normalizeTaxonomyValue("   "), null);
  assertEquals(normalizeTaxonomyValue("Unknown"), null);
  assertEquals(normalizeTaxonomyValue(" unknown "), null);
});

Deno.test("normalizeTaxonomyValue preserves real taxonomy labels", () => {
  assertEquals(normalizeTaxonomyValue("Plantae"), "Plantae");
  assertEquals(normalizeTaxonomyValue(" Malvales "), "Malvales");
});

Deno.test("coalesceTaxonomyValue chooses the first usable taxonomy value", () => {
  assertEquals(coalesceTaxonomyValue(null, "Unknown", "Malvaceae"), "Malvaceae");
  assertEquals(coalesceTaxonomyValue("Unknown", " ", null), null);
});

Deno.test("hasUsableLookalikeTaxonomy requires real kingdom plus order or family", () => {
  assertEquals(hasUsableLookalikeTaxonomy({ kingdom: "Plantae", order: "Malvales", family: null }), true);
  assertEquals(hasUsableLookalikeTaxonomy({ kingdom: "Plantae", order: null, family: "Malvaceae" }), true);
  assertEquals(hasUsableLookalikeTaxonomy({ kingdom: "Unknown", order: "Malvales", family: null }), false);
  assertEquals(hasUsableLookalikeTaxonomy({ kingdom: "Plantae", order: "Unknown", family: null }), false);
  assertEquals(hasUsableLookalikeTaxonomy({ kingdom: "Plantae", order: null, family: null }), false);
});
