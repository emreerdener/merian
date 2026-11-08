import { assert, assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/cpm-verification-current-response-schema-v1.json" with {
  type: "json",
};
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261102223819_prepare_initial_cpm_verification_current.sql",
    import.meta.url,
  ),
);
Deno.test("CPM current assertion shares a closed observation schema and cannot renew a start", () => {
  const found = [...sql.matchAll(/\$json\$(.*?)\$json\$/gs)];
  assertEquals(found.length, 1);
  assertEquals(JSON.parse(found[0][1]), schema);
  assertEquals(schema.properties.authority.enum, ["none"]);
  assert(
    !/CREATE OR REPLACE|CREATE TABLE|UPDATE internal\.|DELETE FROM|INSERT INTO internal\.(?!privileged_routine_grants)/i
      .test(sql),
  );
  assert(!sql.includes("begin_initial_cpm_photo_verification("));
  assert(
    sql.includes(
      "internal.initial_cpm_verification_start_snapshot(p_owner,p_scan)",
    ),
  );
});
Deno.test("CPM current assertion retains owner-before-cohort order and final original deadline", () => {
  let previous = -1;
  for (
    const anchor of [
      "internal.lock_initial_preparation_scope(p_owner,p_scan)",
      "WHERE scan_id=p_scan FOR UPDATE",
      "internal.lock_initial_cpm_photo_capacity()",
      "PERFORM object_id FROM internal.initial_preparation_source_registry",
      "PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts",
      "snapshot:=internal.initial_cpm_verification_start_snapshot",
      "FOR SHARE NOWAIT",
      "result:=jsonb_build_object",
      "now_at:=clock_timestamp();\n IF now_at<saved.cpm_verification_started_at OR now_at>=saved.expires_at",
      "RETURN result",
    ]
  ) {
    const position = sql.indexOf(anchor, previous + 1);
    assert(position > previous, anchor);
    previous = position;
  }
  assert(
    sql.includes(
      "REVOKE ALL ON FUNCTION internal.assert_initial_cpm_verification_current(UUID,UUID,TEXT,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role",
    ),
  );
});
