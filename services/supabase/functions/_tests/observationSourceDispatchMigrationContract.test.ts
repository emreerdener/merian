import { assert } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008222349_prepare_source_dispatch_witness.sql",
    import.meta.url,
  ),
);
Deno.test("source dispatch witness is private, intent owned and transaction bound", () => {
  assert(
    sql.includes("source_dispatch_enabled BOOLEAN NOT NULL DEFAULT FALSE"),
  );
  assert(
    sql.includes(
      "REFERENCES internal.observation_analysis_intents(analysis_id) ON DELETE CASCADE",
    ),
  );
  assert(!sql.includes("REFERENCES internal.ai_quota_reservations"));
  assert(
    sql.includes("w.dispatch_transaction=pg_catalog.pg_current_xact_id()"),
  );
  assert(sql.includes("w.provenance=p_provenance"));
  assert(sql.includes("internal.finalize_ai_quota_reservation_core"));
  assert(
    sql.includes(
      "internal.observation_analysis_dispatch_witnesses WHERE analysis_id=OLD.analysis_id",
    ),
  );
  assert(!/GRANT |cron\.(?:schedule|unschedule)/.test(sql));
});
