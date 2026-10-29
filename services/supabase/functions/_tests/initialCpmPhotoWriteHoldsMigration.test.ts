import { assert, assertEquals } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261029031705_prepare_initial_cpm_photo_write_holds.sql",
    import.meta.url,
  ),
);

Deno.test("CPM write holds install no application capability or closure authority", () => {
  assert(!/GRANT\s/i.test(sql));
  assert(!/CREATE(?: OR REPLACE)? FUNCTION public\./.test(sql));
  assert(
    !/INSERT INTO internal\.(?:initial_preparation_installations|initial_preparation_backend_eligibility|initial_cpm_photo_profiles)/
      .test(sql),
  );
  assert(!sql.includes("SET initial_analysis_lifecycle_enabled=TRUE"));
  assert(sql.includes("ENABLE ROW LEVEL SECURITY"));
  assert(
    sql.includes(
      "REVOKE ALL ON internal.initial_cpm_photo_write_attempts FROM PUBLIC,anon,authenticated,service_role",
    ),
  );
  assert(sql.includes("p_action NOT IN ('bind','status','may_have_issued')"));
});

Deno.test("CPM permanent write identity retains no private declaration or bearer", () => {
  const columns =
    sql.split("CREATE TABLE internal.initial_cpm_photo_write_attempts(")[1]
      .split("\n);")[0];
  for (
    const privateField of [
      "owner_id",
      "canonical_candidate",
      "canonical_assignment",
      "sha256",
      "content_type",
      "signed_url",
      "token",
      "byte_count",
    ]
  ) {
    assert(!columns.includes(privateField), privateField);
  }
  assert(columns.includes("UNIQUE"));
  assert(
    columns.includes(
      "LEAST(admission_expires_at,created_at+INTERVAL '10 minutes')",
    ),
  );
  assert(
    sql.includes("CREATE UNIQUE INDEX initial_cpm_photo_one_outstanding_write"),
  );
  assert(
    sql.includes(
      "BEFORE TRUNCATE ON internal.initial_cpm_photo_write_attempts",
    ),
  );
});

Deno.test("CPM outstanding retirement preserves capacity independently of marker acknowledgement", () => {
  const retire = sql.split(
    "CREATE OR REPLACE FUNCTION internal.retire_initial_preparation_source_objects",
  )[1].split("END; $function$;")[0];
  assert(retire.includes("AND write_capability_state='never_issued'"));
  assert(
    sql.includes(
      "AND NOT internal.initial_cpm_photo_retired_write_hold(identity)",
    ),
  );
  assertEquals((sql.match(/SET state='released'/g) ?? []).length, 1);
  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION public.finish_initial_preparation_source_erasure",
    ),
  );
});

Deno.test("CPM metadata action preserves outer lock order and replays before new eligibility", () => {
  const action =
    sql.split("CREATE FUNCTION internal.initial_cpm_photo_write_action(")[1];
  const markers = [
    "lock_initial_preparation_scope",
    "lock_initial_cpm_photo_capacity",
    "SELECT * INTO registry",
    "SELECT * INTO attempt",
    "THEN RETURN attempt",
    "now_at:=",
    "initial_preparation_backend_eligibility",
  ];
  const positions = markers.map((marker) => action.indexOf(marker));
  assert(positions.every((value) => value >= 0));
  assertEquals(positions, [...positions].sort((a, b) => a - b));
  assert(
    action.includes(
      "internal.assert_initial_preparation_unfunded(p_owner,p_scan)",
    ),
  );
});

Deno.test("raw CPM writes serialize with retirement and released cohorts reject live attempts", () => {
  const guard = sql.split(
    "CREATE FUNCTION internal.guard_initial_cpm_photo_write_attempt()",
  )[1].split("END; $$;")[0];
  assert(
    guard.indexOf("lock_initial_cpm_photo_capacity") <
      guard.indexOf("SELECT * INTO saved"),
  );
  assert(
    guard.includes(
      "WHERE scan_id=NEW.scan_id AND object_id=NEW.object_id FOR UPDATE",
    ),
  );
  const terminal = sql.split(
    "CREATE OR REPLACE FUNCTION internal.require_initial_cpm_photo_cohort()",
  )[1].split("END; $$;")[0];
  assert(
    terminal.includes(
      "initial_cpm_photo_write_attempts WHERE scan_id=identity AND NOT retired",
    ),
  );
});
