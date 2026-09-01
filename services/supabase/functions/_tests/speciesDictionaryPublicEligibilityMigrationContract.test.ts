import { assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260901180000_add_public_biological_species_eligibility.sql",
  import.meta.url,
);
const catalogTestUrl = new URL(
  "../../tests/species_dictionary_public_eligibility.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("species dictionary eligibility is database-owned and indexed for both keysets", async () => {
  const migration = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "ADD COLUMN is_public_biological BOOLEAN GENERATED ALWAYS AS",
      "COALESCE(gbif_taxon_key, 0) > 0",
      "LOWER(pg_catalog.BTRIM(kingdom)) NOT IN",
      "CREATE INDEX idx_species_dictionary_public_biological_name ON public.species_dictionary (scientific_name, id) WHERE is_public_biological",
      "CREATE INDEX idx_species_dictionary_public_biological_created_at ON public.species_dictionary (created_at DESC, id DESC) WHERE is_public_biological",
      "AND species.is_public_biological",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(migration, fragment);
  }
});

Deno.test("species dictionary eligibility has executable database fixtures", async () => {
  const catalogTest = normalized(await Deno.readTextFile(catalogTestUrl));

  for (
    const fragment of [
      "attribute.attgenerated = 's'",
      "a positive GBIF taxon key is publicly biological",
      "a meaningful kingdom plus lower taxonomy is publicly biological",
      "placeholder taxonomy and blank scientific names remain ineligible",
      "eligibility recomputes automatically when taxonomy becomes meaningful",
    ]
  ) {
    assertStringIncludes(catalogTest, fragment);
  }
});
