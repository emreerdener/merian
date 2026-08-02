import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migrationsDir = new URL("../../migrations/", import.meta.url);
const countryOccurrenceDatabaseTest = new URL(
  "../../tests/species_country_occurrences_security.sql",
  import.meta.url,
);

async function migrationSql(fileName: string): Promise<string> {
  return await Deno.readTextFile(new URL(fileName, migrationsDir));
}

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("species dictionary enrichment migration queues missing content from every insert path", async () => {
  const sql = normalized(
    await migrationSql(
      "20260707153931_species_dictionary_enrichment_queue_backfill.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.species_dictionary_missing_enrichment_groups",
      "CREATE OR REPLACE FUNCTION public.enqueue_species_dictionary_enrichment_jobs()",
      "CREATE TRIGGER trg_species_dictionary_enqueue_enrichment_jobs AFTER INSERT ON public.species_dictionary",
      "PERFORM public.enqueue_species_enrichment_jobs( NEW.id, 'species_dictionary_insert', 90, missing_groups )",
      "public.species_dictionary_missing_enrichment_groups(sd) AS missing_groups",
      "'species_dictionary_sparse_backfill'",
      "REVOKE ALL ON FUNCTION public.enqueue_species_dictionary_enrichment_jobs() FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.enqueue_species_dictionary_enrichment_jobs() TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("AFTER INSERT OR UPDATE ON public.species_dictionary"),
    "content refresh updates must not continuously reopen completed enrichment jobs",
  );
});

Deno.test("species dictionary enrichment migration maps content gaps to the existing workers", async () => {
  const sql = normalized(
    await migrationSql(
      "20260707153931_species_dictionary_enrichment_queue_backfill.sql",
    ),
  );

  for (
    const fragment of [
      "missing_groups := ARRAY_APPEND(missing_groups, 'gbif_wikipedia_reference')",
      "missing_groups := ARRAY_APPEND(missing_groups, 'habitat')",
      "missing_groups := ARRAY_APPEND(missing_groups, 'lookalikes')",
      "missing_groups := ARRAY_APPEND(missing_groups, 'group_tags')",
      "FROM public.species_reference_images ref",
      "FROM public.species_lookalikes lookalike",
      "has_public_overview := LENGTH(BTRIM(COALESCE((species_row).wikipedia_overview, ''))) >= 60",
      "has_gbif_taxon := COALESCE((species_row).gbif_taxon_key, 0) > 0",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("missing_groups || '"),
    "content group appends must not rely on ambiguous array concatenation",
  );
});

Deno.test("species country occurrence migration creates a deny-by-default canonical index", async () => {
  const sql = normalized(
    await migrationSql(
      "20260731151344_add_species_country_occurrence_index.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE TABLE public.species_country_occurrences",
      "PRIMARY KEY (species_id, country_code)",
      "country_code = UPPER(country_code)",
      "CHECK (occurrence_count > 0)",
      "CREATE INDEX idx_species_country_occurrences_country ON public.species_country_occurrences ( country_code, occurrence_count DESC, species_id )",
      "ALTER TABLE public.species_country_occurrences ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL PRIVILEGES ON TABLE public.species_country_occurrences FROM PUBLIC, anon, authenticated, service_role",
      "GRANT SELECT, INSERT, DELETE ON TABLE public.species_country_occurrences TO service_role",
      "ALTER COLUMN native_region SET DEFAULT 'Unknown'",
      "NOTIFY pgrst, 'reload schema'",
      "'country_occurrences'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("CREATE POLICY"),
    "country occurrence rows must remain service-owned rather than directly exposed",
  );
});

Deno.test("species country occurrence migration refreshes atomically and reads exact ISO countries", async () => {
  const sql = normalized(
    await migrationSql(
      "20260731151344_add_species_country_occurrence_index.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.replace_species_country_occurrences",
      "SECURITY INVOKER SET search_path = ''",
      "'merian-species-country-occurrence:' || p_species_id::TEXT",
      "'merian-species-country-occurrence:' || NEW.id::TEXT",
      "pg_catalog.PG_ADVISORY_XACT_LOCK",
      "DELETE FROM public.species_country_occurrences AS occurrence WHERE occurrence.species_id = p_species_id",
      "GROUP BY UPPER(item.value ->> 'country_code')",
      "CREATE OR REPLACE FUNCTION public.get_species_dictionary_country_summaries",
      "occurrence.occurrence_count >= GREATEST( COALESCE(p_min_occurrence_count, 1), 1 )",
      "LIMIT LEAST( GREATEST(COALESCE(p_max_rows, 24), 1), 250 )",
      "OR occurrence.country_code = UPPER(pg_catalog.BTRIM(p_country_code))",
      "species.gbif_taxon_key::BIGINT = occurrence.gbif_taxon_key",
      "CREATE OR REPLACE FUNCTION public.invalidate_species_country_occurrences_on_gbif_change",
      "AFTER UPDATE OF gbif_taxon_key ON public.species_dictionary",
      "WHEN (OLD.gbif_taxon_key IS DISTINCT FROM NEW.gbif_taxon_key)",
      "refresh_after = pg_catalog.NOW()",
      "'invalidated_by', 'gbif_taxon_key_change'",
      "'species_gbif_taxon_key_change'",
      "ARRAY['gbif_wikipedia_reference']::TEXT[]",
      "GRANT EXECUTE ON FUNCTION public.replace_species_country_occurrences",
      "GRANT EXECUTE ON FUNCTION public.get_species_dictionary_country_summaries",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !/pg_catalog\.(?:GREATEST|LEAST)\s*\(/i.test(sql),
    "PostgreSQL conditional expressions must not be schema-qualified",
  );
  assert(
    !sql.includes("FOR SHARE"),
    "the invoker RPC must not require dictionary UPDATE privilege just to synchronize a refresh",
  );
  assertEquals(
    sql.match(/pg_catalog\.PG_ADVISORY_XACT_LOCK/g)?.length,
    2,
    "replacement and GBIF-key invalidation must take the same transaction lock",
  );
});

Deno.test("species country occurrence migration reuses the durable GBIF worker and backfills coverage", async () => {
  const sql = normalized(
    await migrationSql(
      "20260731151344_add_species_country_occurrence_index.sql",
    ),
  );

  for (
    const fragment of [
      "has_country_occurrences BOOLEAN := FALSE",
      "FROM public.species_country_occurrences AS occurrence",
      "provenance.content_key = 'country_occurrences'",
      "provenance.metadata ->> 'gbif_taxon_key' = (species_row).gbif_taxon_key::TEXT",
      "AND has_country_occurrences",
      "'species_country_occurrence_backfill'",
      "ARRAY['gbif_wikipedia_reference']::TEXT[]",
      "public.enqueue_species_enrichment_jobs",
      "CREATE OR REPLACE FUNCTION public.species_dictionary_missing_enrichment_groups( species_row public.species_dictionary ) RETURNS TEXT[] LANGUAGE PLPGSQL STABLE SECURITY DEFINER SET search_path = ''",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("species country occurrence database test covers behavior and lifecycle security", async () => {
  const sql = await Deno.readTextFile(countryOccurrenceDatabaseTest);

  for (
    const fragment of [
      "SET LOCAL ROLE service_role",
      "species_country_occurrences_taxon_mismatch",
      "species_country_occurrences_invalid_entry",
      "a valid empty GBIF facet is a successful atomic replacement",
      "a GBIF rematch purges stale rows, invalidates provenance, and queues repair",
      "a successful empty current facet counts as hydrated country coverage",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertStringIncludes(sql, "SELECT extensions.plan(21)");
  assertEquals(
    sql.match(/^SELECT extensions\.(?:ok|is|throws_ok)\(/gm)?.length,
    21,
    "Country occurrence pgTAP plan must match its executable assertions.",
  );
});

Deno.test("reference image suppression migration removes and permanently skips the exact media", async () => {
  const sql = normalized(
    await migrationSql(
      "20260719023147_suppress_european_wildcat_roadkill_image.sql",
    ),
  );

  for (
    const fragment of [
      "DELETE FROM public.species_reference_images",
      "UPDATE public.species_dictionary AS species SET reference_image_url",
      "CREATE OR REPLACE FUNCTION public.public_species_reference_image_urls",
      "CREATE OR REPLACE FUNCTION public.public_species_first_reference_image_url",
      "CREATE OR REPLACE FUNCTION public.suppress_blocked_species_reference_image()",
      "RETURN NULL",
      "CREATE TRIGGER suppress_blocked_species_reference_image BEFORE INSERT OR UPDATE OF url",
      "photos/605615444/",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("WHERE LOWER(BTRIM(url)) LIKE '%felis silvestris%'"),
    "suppression must remain scoped to the exact media rather than the taxon",
  );
});
