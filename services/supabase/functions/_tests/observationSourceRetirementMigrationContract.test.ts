import { assert } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008223804_prepare_atomic_source_execution_retirement.sql",
    import.meta.url,
  ),
);
Deno.test("source retirement releases only proven terminal occupancy and keeps replay first", () => {
  assert(
    sql.includes("source_retirement_enabled BOOLEAN NOT NULL DEFAULT FALSE"),
  );
  assert(
    sql.includes(
      "binding:=internal.lock_observation_evidence_source(p_owner,observation,analysis)",
    ),
  );
  assert(sql.includes("TG_TABLE_NAME='observation_analysis_source_occupancy'"));
  assert(sql.includes("q.state='refunded' AND q.refund_count=1"));
  assert(sql.includes("internal.observation_analysis_dispatch_witnesses"));
  assert(sql.includes("internal.finalize_ai_quota_reservation_core"));
  assert(
    sql.includes("DELETE FROM internal.observation_analysis_source_occupancy"),
  );
  assert(!/GRANT |cron\.(?:schedule|unschedule)/.test(sql));
});
