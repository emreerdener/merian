import { assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260904190000_harden_user_species_preferences_rls.sql",
  import.meta.url,
);
const catalogTestUrl = new URL(
  "../../tests/species_preference_rls_security.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("species preference RLS is account-scoped and least-privilege", async () => {
  const migration = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "ALTER TABLE public.user_species_preferences ENABLE ROW LEVEL SECURITY",
      "CREATE POLICY user_species_preferences_manage_own ON public.user_species_preferences FOR ALL TO authenticated",
      "USING ((SELECT auth.uid()) = user_id)",
      "WITH CHECK ((SELECT auth.uid()) = user_id)",
      "REVOKE ALL ON TABLE public.user_species_preferences FROM PUBLIC, anon",
      "REVOKE ALL ON TABLE public.user_species_preferences FROM authenticated",
      "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_species_preferences TO authenticated",
    ]
  ) {
    assertStringIncludes(migration, fragment);
  }
});

Deno.test("species preference RLS has executable owner and resource-limit coverage", async () => {
  const catalogTest = normalized(await Deno.readTextFile(catalogTestUrl));

  for (
    const fragment of [
      "relation.relrowsecurity",
      "roles = ARRAY['authenticated']::NAME[]",
      "HAS_TABLE_PRIVILEGE( 'anon', 'public.user_species_preferences', 'SELECT' )",
      "HAS_TABLE_PRIVILEGE( 'authenticated', 'public.user_species_preferences', 'TRUNCATE' )",
      "owner A can read another account preference",
      "owner A could not update an owned preference",
      "owner A updated another account preference",
      "owner A deleted another account preference",
      "owner A inserted another account preference",
      "owner A could not delete an owned preference",
      "preferred-name length constraint accepted 201 characters",
      "owner B can read another account preference",
      "anonymous caller read account species preferences",
    ]
  ) {
    assertStringIncludes(catalogTest, fragment);
  }
});
