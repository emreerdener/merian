import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260803180211_harden_collection_ownership_and_memberships.sql",
  import.meta.url,
);
const catalogFixtureUrl = new URL(
  "../../tests/collection_ownership_security.sql",
  import.meta.url,
);
const ordinalityRepairMigrationUrl = new URL(
  "../../migrations/20260803215309_fix_collection_owner_upsert_ordinality.sql",
  import.meta.url,
);
const invokerPrivilegesMigrationUrl = new URL(
  "../../migrations/20260803215310_grant_collection_sync_invoker_privileges.sql",
  import.meta.url,
);
const membershipConflictRepairMigrationUrl = new URL(
  "../../migrations/20260804002819_fix_collection_membership_conflict_ambiguity.sql",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/--.*$/gm, "").replaceAll(/\s+/g, " ").trim();
}

Deno.test("collection ownership upsert is atomic, owner-guarded, and service-only", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.upsert_owned_collections( p_user_id UUID, p_collections JSONB )",
      "SECURITY INVOKER SET search_path = ''",
      "INSERT INTO public.collections AS existing",
      "ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, created_at = EXCLUDED.created_at WHERE existing.user_id = EXCLUDED.user_id",
      "written.id IS NOT NULL",
      "REVOKE ALL ON FUNCTION public.upsert_owned_collections(UUID, JSONB) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.upsert_owned_collections(UUID, JSONB) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("SET user_id = EXCLUDED.user_id"),
    "A UUID collision must never reparent an existing collection.",
  );
});

Deno.test("collection memberships require two owner-matched parents at every write boundary", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "DELETE FROM public.collection_scans AS membership USING public.collections AS collection, public.scans AS scan",
      "collection.user_id IS DISTINCT FROM scan.user_id",
      "CREATE OR REPLACE FUNCTION public.insert_owned_collection_scans( p_user_id UUID, p_rows JSONB )",
      "collection.user_id = p_user_id JOIN public.scans AS scan",
      "scan.user_id = p_user_id",
      "CREATE TRIGGER enforce_collection_scan_owner_match BEFORE INSERT OR UPDATE OF collection_id, scan_id ON public.collection_scans",
      'CREATE POLICY "Users can read their own collection scans"',
      'CREATE POLICY "Users can delete their own collection scans"',
      'CREATE POLICY "Users can add scans to their own collections"',
      "scan.user_id = (SELECT auth.uid())",
      "GRANT EXECUTE ON FUNCTION public.insert_owned_collection_scans(UUID, JSONB) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("service collection writes cannot update ownership directly", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "REVOKE UPDATE ON TABLE public.collections FROM service_role",
      "REVOKE UPDATE (id, user_id, name, created_at) ON TABLE public.collections FROM service_role",
      "GRANT UPDATE (name, created_at) ON TABLE public.collections TO service_role",
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '30s'",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("collection catalog fixture recognizes PostgreSQL's empty search-path setting", async () => {
  const fixture = compact(await Deno.readTextFile(catalogFixtureUrl));

  assertStringIncludes(
    fixture,
    "COALESCE( routine.proconfig, ARRAY[]::TEXT[] ) @> ARRAY['search_path=\"\"']::TEXT[]",
  );
  assert(
    !fixture.includes("ARRAY['search_path=']::TEXT[]"),
    "PostgreSQL records SET search_path = '' as search_path=\"\" in proconfig.",
  );
});

Deno.test("collection upsert forward migration uses valid JSON-array ordinality", async () => {
  const sql = compact(await Deno.readTextFile(ordinalityRepairMigrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.upsert_owned_collections( p_user_id UUID, p_collections JSONB )",
      "SECURITY INVOKER SET search_path = ''",
      "FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_collections) WITH ORDINALITY AS source(value, ordinality)",
      "CROSS JOIN LATERAL pg_catalog.JSONB_TO_RECORD(source.value) AS parsed( id UUID, name TEXT, created_at TIMESTAMPTZ )",
      "source.ordinality",
      "ORDER BY input_rows.id, input_rows.ordinality DESC",
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '30s'",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("JSONB_TO_RECORDSET(p_collections) WITH ORDINALITY"),
    "WITH ORDINALITY must be attached to jsonb_array_elements, not jsonb_to_recordset with a column definition list.",
  );
});

Deno.test("collection invoker routines have only their required service table privileges", async () => {
  const sql = compact(await Deno.readTextFile(invokerPrivilegesMigrationUrl));

  for (
    const fragment of [
      "GRANT SELECT, INSERT, DELETE ON TABLE public.collections TO service_role",
      "GRANT SELECT ON TABLE public.scans TO service_role",
      "GRANT SELECT, INSERT, DELETE ON TABLE public.collection_scans TO service_role",
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '30s'",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("GRANT UPDATE ON TABLE public.collections TO service_role"),
    "The invoker repair must not restore table-wide collection ownership updates.",
  );
});

Deno.test("collection membership insert avoids RETURNS TABLE conflict-target ambiguity", async () => {
  const sql = compact(
    await Deno.readTextFile(membershipConflictRepairMigrationUrl),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.insert_owned_collection_scans( p_user_id UUID, p_rows JSONB )",
      "SECURITY INVOKER SET search_path = ''",
      "ON CONFLICT ON CONSTRAINT collection_scans_pkey DO NOTHING",
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '30s'",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("ON CONFLICT (collection_id, scan_id)"),
    "The output parameter names make an unqualified conflict column list ambiguous in PL/pgSQL.",
  );
});
