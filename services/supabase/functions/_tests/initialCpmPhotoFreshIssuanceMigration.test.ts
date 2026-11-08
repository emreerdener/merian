import { assert, assertEquals } from "@std/assert";

const sql = Deno.readTextFileSync(
  new URL(
    "../../migrations/20261029222909_prepare_initial_cpm_photo_fresh_issuance.sql",
    import.meta.url,
  ),
);

Deno.test("fresh CPM issuance is one guarded service boundary with no installation", () => {
  assertEquals((sql.match(/SECURITY DEFINER/g) ?? []).length, 1);
  assert(sql.includes("PERFORM internal.require_service_role()"));
  assert(sql.includes("SET search_path='' SET statement_timeout='5s'"));
  assert(sql.includes("FROM PUBLIC,anon,authenticated"));
  assert(sql.includes("TO service_role"));
  assert(
    sql.includes(
      "'public.begin_initial_cpm_photo_write(uuid,uuid,text,uuid,text)'",
    ),
  );
  assert(sql.includes("internal.privileged_routine_grants"));
  assert(!/INSERT INTO internal.initial_cpm_photo_write_policies/.test(sql));
  assert(!/UPDATE internal.initial_analysis_rollout/.test(sql));
  assert(!/GRANT (ALL|INSERT|UPDATE|SELECT|DELETE)/.test(sql));
});

Deno.test("fresh CPM transition reuses the locked owners and returns no replay snapshot", () => {
  const bound = sql.indexOf("initial_cpm_photo_write_action('bind'");
  const held = sql.indexOf("'outcome','held'");
  const policy = sql.indexOf("a:=internal.bind_initial_cpm_photo_write_policy");
  const advance = sql.indexOf(
    "initial_cpm_photo_write_action('may_have_issued'",
  );
  const snapshot = sql.indexOf(
    "observation:=internal.read_initial_cpm_photo_observation",
  );
  const fresh = sql.indexOf("'outcome','fresh'");
  assert(bound > 0 && bound < held && held < policy && policy < advance);
  assert(advance < snapshot && snapshot < fresh);
  assert(
    sql.includes("a.state='may_have_issued' OR a.retired OR a.write_closed"),
  );
  assert(
    sql.includes(
      "RETURN jsonb_build_object('outcome','held','attempt_id',a.attempt_id)",
    ),
  );
  assert(!/UPDATE internal.initial_cpm_photo_write_attempts/.test(sql));
  assert(!/UPDATE internal.initial_cpm_photo_capacity_reservations/.test(sql));
  assert(!/DELETE FROM/.test(sql));
});
