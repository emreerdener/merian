import { assert } from "@std/assert";

Deno.test("capture staging contract reuses V9 budgets without creating upload or execution authority", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120194518_validate_initial_capture_staging_plan.sql",
      import.meta.url,
    ),
  );
  assert(
    sql.includes(
      "internal.initial_evidence_contract(jsonb_build_object('schema_version',9",
    ),
  );
  assert(sql.includes("SECURITY INVOKER SET search_path = ''"));
  assert(
    sql.includes(
      "REVOKE ALL ON FUNCTION internal.initial_capture_plan_contract(UUID,JSONB) FROM PUBLIC,anon,authenticated,service_role",
    ),
  );
  assert(
    sql.includes(
      "pair#>'{source,content_type}' IS DISTINCT FROM '\"audio/wav\"'::JSONB",
    ),
  );
  assert(sql.includes("'prepared_media_id',artifact->'media_id'"));
  assert(
    !/CREATE TABLE|SECURITY DEFINER|GRANT |UPDATE |INSERT INTO |DELETE FROM |cron\.schedule/i
      .test(sql),
  );
});
