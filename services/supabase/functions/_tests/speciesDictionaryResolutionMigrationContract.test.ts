import { assert, assertStringIncludes } from "@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260921043256_resolve_verified_dictionary_species.sql",
    import.meta.url,
  ),
);
const sql = migration.replaceAll(/\s+/g, " ");
Deno.test("species resolution preserves service-only materialization and independent bounded admission", () => {
  for (
    const [name, signature] of [
      ["admit_species_dictionary_resolution", "UUID"],
      ["resolve_verified_dictionary_species", "JSONB"],
    ]
  ) {
    assertStringIncludes(
      sql,
      `REVOKE ALL ON FUNCTION public.${name}(${signature}) FROM PUBLIC, anon, authenticated, service_role`,
    );
    assertStringIncludes(
      sql,
      `GRANT EXECUTE ON FUNCTION public.${name}(${signature}) TO service_role`,
    );
    assertStringIncludes(
      sql,
      `'service_role', 'public.${name}(${signature.toLowerCase()})'`,
    );
  }
  assert(
    migration.match(/PERFORM internal.require_service_role\(\)/g)?.length === 2,
  );
  assert(
    migration.match(/SECURITY DEFINER SET search_path = ''/g)?.length === 2,
  );
  assertStringIncludes(sql, "minute_start, 60, 6");
  assertStringIncludes(sql, "day_start, 86400, 60");
  assertStringIncludes(sql, "minute_start, 60, 120");
  assert(!sql.includes("reserve_ai_quota"));
  assertStringIncludes(sql, "ON CONFLICT (scientific_name) DO NOTHING");
  assertStringIncludes(
    sql,
    "ON public.species_dictionary (gbif_taxon_key) WHERE gbif_taxon_key IS NOT NULL",
  );
  assertStringIncludes(sql, "PG_ADVISORY_XACT_LOCK(187394, taxon_key)");
  assertStringIncludes(
    sql,
    "resolved.gbif_taxon_key IS DISTINCT FROM taxon_key",
  );
  assertStringIncludes(
    sql,
    "UPDATE public.species_dictionary SET gbif_taxon_key = taxon_key WHERE scientific_name = canonical_name AND is_public_biological AND gbif_taxon_key IS NULL",
  );
  assertStringIncludes(sql, "merian.lookalike_candidate_materialization");
});
