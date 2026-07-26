import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260726212549_harden_service_role_request_authentication.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("taxonomy import history is inaccessible to public API roles", async () => {
  const migration = normalized(await Deno.readTextFile(migrationUrl));

  assertStringIncludes(
    migration,
    "REVOKE ALL PRIVILEGES ON TABLE public.taxonomy_import_runs FROM PUBLIC, anon, authenticated, service_role",
  );
  assertStringIncludes(
    migration,
    "GRANT SELECT, INSERT, UPDATE ON TABLE public.taxonomy_import_runs TO service_role",
  );
  assert(
    !migration.includes(
      "GRANT DELETE ON TABLE public.taxonomy_import_runs TO service_role",
    ),
    "Taxonomy workers do not require DELETE access to import history.",
  );
  assertStringIncludes(migration, "NOTIFY pgrst, 'reload schema'");
});
