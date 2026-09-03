import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260903163744_recover_species_lookalike_enrichment.sql",
    import.meta.url,
  ),
);
const normalized = migration.replaceAll(/\s+/g, " ");

function routine(name: string): string {
  const start = migration.indexOf(`CREATE FUNCTION public.${name}(`);
  assert(start >= 0, `Missing recovery RPC ${name}`);
  const end = migration.indexOf("\n$$;", start);
  assert(end > start, `Unterminated recovery RPC ${name}`);
  return migration.slice(start, end).replaceAll(/\s+/g, " ");
}

Deno.test("lookalike recovery migration - worker RPCs have explicit service-only contracts", () => {
  for (
    const [name, identity] of [
      [
        "claim_species_model_enrichment_jobs",
        "integer,timestamp with time zone,text[],boolean",
      ],
      ["persist_species_model_lookalikes", "uuid,jsonb,boolean"],
    ]
  ) {
    const declaration = routine(name);
    assertStringIncludes(declaration, "SECURITY DEFINER SET search_path = ''");
    assertStringIncludes(
      declaration,
      "PERFORM internal.require_service_role()",
    );
    assertStringIncludes(
      normalized,
      `'service_role', 'public.${name}(${identity})'`,
    );
  }
  assertStringIncludes(
    normalized,
    "REVOKE ALL ON FUNCTION public.persist_species_model_lookalikes(UUID, JSONB, BOOLEAN) FROM PUBLIC, anon, authenticated, service_role",
  );
  assertStringIncludes(
    normalized,
    "REVOKE ALL ON FUNCTION public.claim_species_model_enrichment_jobs(INTEGER, TIMESTAMPTZ, TEXT[], BOOLEAN) FROM PUBLIC, anon, authenticated, service_role",
  );
  assertStringIncludes(
    routine("persist_species_model_lookalikes"),
    "RETURNS TABLE (persisted_count INTEGER, unresolved_count INTEGER, rejected_count INTEGER)",
  );
  assertStringIncludes(
    routine("persist_species_model_lookalikes"),
    "resolution_complete BOOLEAN DEFAULT TRUE",
  );
});

Deno.test("lookalike recovery migration - preview is read-only and migration alone cannot reopen legacy work", () => {
  const claim = routine("claim_species_model_enrichment_jobs");
  const preview = claim.slice(
    claim.indexOf("IF preview_only THEN"),
    claim.indexOf("RETURN; END IF;"),
  );
  assertStringIncludes(preview, "lookalike_resolution_version");
  assert(!/\b(?:UPDATE|INSERT|DELETE)\b/.test(preview));
  assertStringIncludes(claim, "FOR UPDATE OF job SKIP LOCKED");
  assertStringIncludes(
    claim,
    "pg_catalog.JSONB_BUILD_OBJECT('lookalike_resolution_version', 1)",
  );
  assert(
    !/\b(?:UPDATE|INSERT|DELETE)\s+.*species_enrichment_jobs/i.test(
      migration.slice(0, migration.indexOf("CREATE FUNCTION")),
    ),
    "Applying the migration before the worker must not reopen old outcomes",
  );
});

Deno.test("lookalike recovery migration - materialization suppresses both recursive generation and genus fan-out", () => {
  assertStringIncludes(
    normalized,
    "missing_groups := pg_catalog.ARRAY_REMOVE(missing_groups, 'lookalikes')",
  );
  assertStringIncludes(
    normalized,
    "CREATE OR REPLACE TRIGGER trg_link_taxonomy_lookalikes AFTER INSERT ON public.species_dictionary FOR EACH ROW WHEN (pg_catalog.CURRENT_SETTING('merian.lookalike_candidate_materialization', TRUE) IS DISTINCT FROM 'on')",
  );
  assertStringIncludes(
    routine("persist_species_model_lookalikes"),
    "COALESCE(previous_materialization_setting, ''), TRUE",
  );
});

Deno.test("lookalike recovery database fixture is transactional and fully planned", async () => {
  const fixture = await Deno.readTextFile(
    new URL(
      "../../tests/species_lookalike_recovery.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(fixture, "BEGIN;");
  assert(fixture.trimEnd().endsWith("ROLLBACK;"));
  const planned = Number(fixture.match(/extensions\.plan\((\d+)\)/)?.[1]);
  const assertions = fixture.match(
    /^SELECT extensions\.(?:ok|throws_ok|pass)\(/gm,
  );
  assertEquals(planned, 10);
  assertEquals(assertions?.length, planned);
});
