import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260724222838_optimize_species_count_trigger.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("species-count migration builds a private incremental ledger", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "LOCK TABLE public.scans IN SHARE ROW EXCLUSIVE MODE",
      "CREATE TABLE internal.user_species_scan_counts",
      "PRIMARY KEY (user_id, species_id)",
      "CHECK (scan_count > 0)",
      "CONSTRAINT user_species_scan_counts_species_id_fkey FOREIGN KEY (species_id) REFERENCES public.species_dictionary(id) ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED",
      "CREATE INDEX user_species_scan_counts_species_idx ON internal.user_species_scan_counts (species_id, user_id)",
      "ALTER TABLE internal.user_species_scan_counts ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.user_species_scan_counts FROM PUBLIC, anon, authenticated, service_role",
      "INSERT INTO internal.user_species_scan_counts",
      "GROUP BY scans.user_id, scans.species_id",
      "UPDATE public.users AS users SET total_species_discovered = totals.species_count",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("COUNT(DISTINCT"),
    "routine scan writes must never recount a user's complete scan history",
  );
});

Deno.test("species-count migration applies boundary-crossing deltas safely", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION internal.apply_user_species_scan_count_deltas",
      "SECURITY DEFINER SET search_path = ''",
      "JOIN ( SELECT DISTINCT deltas.user_id",
      "ORDER BY users.id FOR NO KEY UPDATE OF users",
      "RAISE EXCEPTION 'user_species_scan_count_underflow'",
      "SET scan_count = counts.scan_count + positive.scan_delta",
      "ON CONFLICT (user_id, species_id) DO NOTHING",
      "users.total_species_discovered + increments.species_count",
      "counts.scan_count <= -negative.scan_delta",
      "users.total_species_discovered - decrements.species_count",
      "REVOKE ALL ON FUNCTION internal.apply_user_species_scan_count_deltas",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertEquals(
    sql.match(/SET search_path = ''/g)?.length,
    5,
    "every definer routine in the migration must pin an empty search_path",
  );
});

Deno.test("species-count triggers aggregate transition tables once per statement", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "DROP TRIGGER IF EXISTS unified_species_count_sync ON public.scans",
      "DROP FUNCTION IF EXISTS public.sync_global_species_count()",
      "AFTER INSERT ON public.scans REFERENCING NEW TABLE AS inserted_scans FOR EACH STATEMENT",
      "AFTER DELETE ON public.scans REFERENCING OLD TABLE AS deleted_scans FOR EACH STATEMENT",
      "AFTER UPDATE ON public.scans REFERENCING OLD TABLE AS previous_scans NEW TABLE AS current_scans FOR EACH STATEMENT",
      "AFTER TRUNCATE ON public.scans FOR EACH STATEMENT",
      "HAVING pg_catalog.SUM(raw_changes.scan_delta) <> 0",
      "previous.user_id",
      "current.user_id",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("FOR EACH ROW"),
    "species-count maintenance must not amplify bulk writes per row",
  );
  assert(
    !sql.includes("app.ghost_profile_merge_skip_scan_derivations"),
    "the incremental ledger must remain active during bulk owner transfers",
  );
});
