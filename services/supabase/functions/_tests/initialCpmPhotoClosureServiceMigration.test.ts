import { assert, assertEquals } from "@std/assert";

const sql = Deno.readTextFileSync(
  new URL(
    "../../migrations/20261029203758_prepare_initial_cpm_photo_closure_service.sql",
    import.meta.url,
  ),
);
Deno.test("CPM closure service exposes only exact allowlisted guarded functions", () => {
  assertEquals((sql.match(/SECURITY DEFINER/g) ?? []).length, 3);
  assertEquals(
    (sql.match(/PERFORM internal.require_service_role\(\)/g) ?? []).length,
    3,
  );
  for (
    const signature of [
      "public.read_initial_cpm_photo_write_closure(uuid,text)",
      "public.read_initial_cpm_photo_observation(uuid,text,uuid,jsonb)",
      "public.settle_initial_cpm_photo_write_closure(uuid,text,text,text,uuid)",
    ]
  ) assert(sql.includes(`'${signature}'`));
  assert(
    sql.includes("REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated"),
  );
  assert(sql.includes("GRANT EXECUTE ON FUNCTION %s TO service_role"));
  assert(
    sql.includes(
      "internal.privileged_routine_grants(role_name,routine_signature,purpose)",
    ),
  );
  assertEquals(
    (sql.match(
      /SECURITY DEFINER SET search_path='' SET statement_timeout='5s'/g,
    ) ?? []).length,
    3,
  );
  assert(!/GRANT (SELECT|ALL|UPDATE|INSERT)/.test(sql));
});
Deno.test("CPM historical receipt read is separate from fresh lifecycle and policy checks", () => {
  const read = sql.split(
    "CREATE FUNCTION public.read_initial_cpm_photo_write_closure",
  )[1]
    .split("END; $$;")[0].replace(/--[^\n]*/g, "");
  assert(read.includes("WHERE attempt_id=p_attempt AND outcome=p_outcome"));
  assert(!read.includes("read_initial_cpm_photo_observation"));
  assert(!read.includes("eligibility"));
  assert(!read.includes("lock_initial_preparation_scope"));
  assert(
    sql.includes(
      "internal.read_initial_cpm_photo_observation(p_attempt,p_outcome,p_claim,p_expected)",
    ),
  );
  assert(!sql.includes("claim_initial_preparation_source_erasure("));
  assert(
    !sql.includes("INSERT INTO internal.initial_cpm_photo_write_policies"),
  );
});
Deno.test("CPM service receipt retains exact microseconds with one existing settlement owner", () => {
  assert(sql.includes("p_observed_at TEXT"));
  assert(sql.includes('SS.US"Z"'));
  assert(sql.includes("observed:=p_observed_at::TIMESTAMPTZ"));
  assert(sql.includes("<>p_observed_at"));
  assert(!sql.includes("extract(epoch"));
  assertEquals(
    (sql.match(/internal.settle_initial_cpm_photo_write_closure\(/g) ?? [])
      .length,
    1,
  );
  assert(
    !sql.includes("UPDATE internal.initial_cpm_photo_capacity_reservations"),
  );
});
