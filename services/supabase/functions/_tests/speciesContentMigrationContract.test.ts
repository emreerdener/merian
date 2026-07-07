import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migrationsDir = new URL("../../migrations/", import.meta.url);

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
