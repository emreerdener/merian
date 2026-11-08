import { assert } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261102173347_prepare_initial_cpm_atomic_admission.sql",
    import.meta.url,
  ),
);

Deno.test("CPM admission construction remains private and uses the existing stage owner", () => {
  assert(!/\bGRANT\s|CREATE(?: OR REPLACE)? FUNCTION public\./i.test(sql));
  assert(!sql.includes("SECURITY DEFINER"));
  assert(!/CREATE TABLE/i.test(sql));
  for (
    const name of [
      "build_initial_cpm_admission_stage",
      "create_initial_admission_stage",
    ]
  ) {
    assert(sql.includes(
      `REVOKE ALL ON FUNCTION internal.${name}(UUID,UUID,TEXT,TEXT)\n FROM PUBLIC,anon,authenticated,service_role`,
    ));
  }
});

Deno.test("CPM admission construction preserves outer then capacity then ordered cohort lock order", () => {
  const anchors = [
    "PERFORM internal.lock_initial_preparation_scope(p_owner,p_scan)",
    "WHERE scan_id=p_scan FOR UPDATE",
    "PERFORM internal.lock_initial_cpm_photo_capacity()",
    "PERFORM object_id FROM internal.initial_preparation_source_registry",
    "PERFORM attempt_id FROM internal.initial_cpm_photo_write_attempts",
    "snapshot:=internal.initial_cpm_verification_start_snapshot(p_owner,p_scan)",
  ];
  let previous = -1;
  for (const anchor of anchors) {
    const position = sql.indexOf(anchor);
    assert(position > previous, `lock order: ${anchor}`);
    previous = position;
  }
});

Deno.test("CPM and legacy proof share accounting assertions without changing legacy receipt domain", () => {
  assert(
    sql.includes(
      "CREATE FUNCTION internal.assert_initial_admitted_accounting(",
    ),
  );
  assert(
    sql.includes(
      "REVOKE ALL ON FUNCTION internal.assert_initial_admitted_accounting(JSONB,JSONB,JSONB,JSONB,JSONB)",
    ),
  );
  assert(sql.includes("initial admitted accounting source drift"));
  assert(sql.includes("merian.initial-analysis.handoff.admitted-receipt.v1"));
  assert(sql.includes("FROM first_at FOR last_at-first_at"));
});

Deno.test("CPM C1 evidence remains private and preserves legacy empty-event denial", () => {
  for (
    const signature of [
      "initial_cpm_cancellation_retained_images(internal.initial_preparation_admission_receipts,BOOLEAN)",
      "assert_initial_cpm_cancellation_images(UUID,JSONB,BOOLEAN)",
      "assert_initial_cpm_cancellation_empty_destination(UUID,JSONB)",
    ]
  ) {
    assert(
      sql.includes(
        `REVOKE ALL ON FUNCTION internal.${signature}\n FROM PUBLIC,anon,authenticated,service_role`,
      ),
    );
  }
  assert(
    sql.includes(
      "internal.assert_initial_cancellation_retirement_images(uuid,text,jsonb,boolean,jsonb)",
    ),
  );
  assert(
    !sql.includes(
      "pg_get_functiondef('internal.assert_initial_cancellation_retirement_images(uuid,text,jsonb,boolean)'",
    ),
  );
  assert(sql.includes("CPM C1 capacity lock drift"));
  assert(sql.includes("CPM merge capacity lock drift"));
});
