import { assert, assertEquals } from "@std/assert";
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011055729_prepare_initial_analysis_private_storage.sql",
    import.meta.url,
  ),
);
Deno.test("Initial storage migration - inaccessible default-off foundation", () => {
  assert(
    migration.includes(
      "initial_analysis_lifecycle_enabled BOOLEAN NOT NULL DEFAULT FALSE",
    ),
  );
  assert(!/\bGRANT\b/i.test(migration));
  assert(!/CREATE(?: OR REPLACE)? FUNCTION public\./i.test(migration));
  for (const table of ["rollout", "submissions", "results", "completions"]) {
    assert(
      migration.includes(
        `ALTER TABLE internal.initial_analysis_${table} ENABLE ROW LEVEL SECURITY`,
      ),
    );
  }
  const functions = [
    ...migration.matchAll(/CREATE FUNCTION (internal\.\w+)\(\)/g),
  ].map((match) => match[1]);
  assertEquals(functions.length, 6);
  for (const name of functions) {
    assert(
      migration.includes(
        `REVOKE ALL ON FUNCTION ${name}() FROM PUBLIC,anon,authenticated,service_role`,
      ),
    );
  }
});
Deno.test("Initial storage migration - permanent namespace and pre-row erasure coverage", () => {
  assert(
    migration.includes("BEFORE INSERT ON internal.scan_deletion_tombstones"),
  );
  assert(migration.includes("BEFORE DELETE ON public.users"));
  assert(
    migration.includes(
      "AFTER UPDATE OF user_id,is_tombstoned OR DELETE ON public.scans",
    ),
  );
  assert(migration.includes("pg_try_advisory_xact_lock"));
  assert(!/DELETE FROM internal\.scan_deletion_tombstones/i.test(migration));
  assert(migration.includes("'preserve',900,NULL"));
});
