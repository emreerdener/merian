import { assert, assertEquals } from "@std/assert";
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011092418_prepare_initial_analysis_cancellation.sql",
    import.meta.url,
  ),
);
Deno.test("IC-1 cancellation installs only a fixed service boundary with no dispatch grant", () => {
  const grants = [
    ...migration.matchAll(/GRANT EXECUTE ON FUNCTION ([^;]+) TO service_role/g),
  ].map((match) => match[1]);
  assertEquals(grants, ["public.cancel_initial_analysis(UUID,UUID)"]);
  assert(!/UPDATE internal\.initial_analysis_rollout SET/i.test(migration));
  assert(
    !/CREATE(?: OR REPLACE)? FUNCTION public\.authorize_initial_analysis_dispatch/i
      .test(migration),
  );
  for (const table of ["lifecycle_fences", "cancellations"]) {
    assert(
      migration.includes(
        `ALTER TABLE internal.initial_analysis_${table} ENABLE ROW LEVEL SECURITY`,
      ),
    );
  }
  assert(migration.includes("'preserve',901,NULL"));
  assert(
    migration.includes(
      "internal.finalize_ai_quota_reservation_core(quota.id,p_owner,quota.lease_token,'refunded')",
    ),
  );
  assert(
    !/DELETE FROM internal\.initial_analysis_operation_fences/i.test(migration),
  );
});
Deno.test("IC-1 cancellation keeps generic tombstone erasure settlement-free", () => {
  const raw = migration.split(
    "CREATE FUNCTION internal.fence_initial_analysis_erasure",
  )[1].split("DO $erasure$")[0];
  assert(!raw.includes("finalize_ai_quota"));
  assert(!raw.includes("settle_complimentary"));
  assert(raw.includes("DELETE FROM internal.initial_analysis_cancellations"));
  assert(migration.includes("initial_analysis_already_complete"));
  assert(migration.includes("initial_analysis_cancelled"));
});
