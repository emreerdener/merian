import { assert, assertEquals } from "@std/assert";

const sql = Deno.readTextFileSync(
  new URL(
    "../../migrations/20261030000315_prepare_initial_cpm_photo_write_status.sql",
    import.meta.url,
  ),
);

Deno.test("CPM status keeps the exact service-only guard and allowlist", () => {
  assertEquals((sql.match(/SECURITY DEFINER/g) ?? []).length, 1);
  assert(sql.includes("PERFORM internal.require_service_role()"));
  assert(sql.includes("SET search_path='' SET statement_timeout='5s'"));
  assert(sql.includes("FROM PUBLIC,anon,authenticated"));
  assert(sql.includes("TO service_role"));
  assert(
    sql.includes(
      "'public.read_initial_cpm_photo_write_status(uuid,uuid,text,uuid)'",
    ),
  );
  assert(sql.includes("internal.privileged_routine_grants"));
  assert(!/GRANT (ALL|INSERT|UPDATE|SELECT|DELETE)/.test(sql));
});

Deno.test("CPM status invokes only nontransition bookkeeping and closes the projection", () => {
  const body = sql.split("AS $$")[1].split("$$;")[0];
  assert(
    body.includes(
      "initial_cpm_photo_write_action('status',p_owner,p_scan,p_digest,p_object)",
    ),
  );
  assert(!/\b(INSERT|UPDATE|DELETE|TRUNCATE)\b/.test(body));
  assert(!/begin_initial|bind_initial|settle_initial/.test(body));
  assert(body.includes("'authority','none'"));
  assert(body.includes("CASE WHEN a.attempt_id IS NULL THEN NULL"));
  assert(
    !/to_jsonb|row_to_json|backend|policy|credential|headers|url/.test(body),
  );
  assert(body.includes("a.assignment_digest IS DISTINCT FROM p_digest"));
  assert(
    body.includes("floor(extract(epoch FROM a.capability_expires_at)*1000)"),
  );
  assert(!/clock_timestamp|now\(\)/i.test(body));
});
