import { assert, assertEquals } from "@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011101320_prepare_initial_analysis_media_allocation.sql",
    import.meta.url,
  ),
);
Deno.test("M1 exposes only metadata/retirement service APIs and seeds no active backend", () => {
  const publicFunctions = [
    ...migration.matchAll(/CREATE FUNCTION public\.([a-z_]+)\(/g),
  ].map((match) => match[1]);
  assertEquals(publicFunctions, [
    "allocate_initial_analysis_media",
    "get_initial_analysis_media",
    "retire_initial_analysis_media",
    "claim_initial_analysis_media_erasure",
    "finish_initial_analysis_media_erasure",
  ]);
  assert(
    !/INSERT INTO internal\.initial_analysis_media_backends/.test(migration),
  );
  assert(!/UPDATE internal\.initial_analysis_rollout/.test(migration));
  assert(
    !/finalize_ai_quota|settle_complimentary|commit_identification_invocation|net\.http|cron\.schedule/i
      .test(migration),
  );
  assert(!/REFERENCES internal\.observation_histories/.test(migration));
  const cleanup = migration.split(
    "CREATE FUNCTION public.claim_initial_analysis_media_erasure()",
  )[1].split("REVOKE ALL ON FUNCTION")[0];
  assert(
    !/public\.users|lock_initial_media_scope|pg_advisory|initial_analysis_submissions/
      .test(cleanup),
  );
  for (
    const table of ["backends", "allocation_fences", "registry", "cohorts"]
  ) {
    assert(
      migration.includes(
        `ALTER TABLE internal.initial_analysis_media_${table} ENABLE ROW LEVEL SECURITY`,
      ),
    );
  }
});
