import { assert, assertEquals } from "@std/assert";
Deno.test("held video storage coordinates namespaces without opening V4 execution", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261010024956_prepare_video_cohort_storage.sql",
      import.meta.url,
    ),
  );
  assertEquals((sql.match(/CREATE TABLE/g) ?? []).length, 1);
  assert(!/\bGRANT\b|CREATE (?:OR REPLACE )?FUNCTION public\./.test(sql));
  for (
    const boundary of [
      "ENABLE ROW LEVEL SECURITY",
      "FROM PUBLIC,anon,authenticated,service_role",
      "lock_owned_observation_video_source_binding",
      "internal.observation_video_source_fingerprint(p_expected_input)",
      "observation_source_child_is_unused",
      "validate_observation_source_binding",
      "public.reserve_owned_observation_analysis_source",
      "public.get_owned_observation_analysis_source",
      "LIMIT 65",
      "validate_observation_source_cohort",
      "ON DELETE CASCADE",
      "BEFORE INSERT OR UPDATE OR DELETE",
    ]
  ) assert(sql.includes(boundary), boundary);
  assert(
    !sql.includes(
      "CREATE FUNCTION internal.observation_storage_source_fingerprint",
    ),
  );
  assert(
    !sql.includes(
      "pg_get_functiondef('internal.observation_source_release_proven",
    ),
  );
});
