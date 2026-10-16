import { assert, assertEquals } from "@std/assert";
Deno.test("held video cohort projection is private and has no persistence or live consumers", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261010015758_prepare_video_cohort_inventory.sql",
      import.meta.url,
    ),
  );
  assertEquals((sql.match(/CREATE FUNCTION/g) ?? []).length, 1);
  assert(sql.includes("STABLE SECURITY INVOKER SET search_path=''"));
  assert(
    sql.includes(
      "PERFORM internal.observation_video_source_fingerprint(p_input)",
    ),
  );
  assert(
    sql.includes(
      "REVOKE ALL ON FUNCTION internal.observation_video_source_cohort_items(JSONB) FROM PUBLIC,anon,authenticated,service_role",
    ),
  );
  assert(
    !/\b(?:INSERT|UPDATE|DELETE|GRANT|SECURITY DEFINER|CREATE TABLE|CREATE TRIGGER)\b/
      .test(sql),
  );
});
