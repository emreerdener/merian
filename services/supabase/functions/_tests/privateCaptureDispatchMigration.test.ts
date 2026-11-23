import { assert } from "@std/assert";

Deno.test("private Capture permit survives accounting pruning and requires atomic fresh authority", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261121083202_fence_private_capture_primary_dispatch.sql",
      import.meta.url,
    ),
  );
  const table =
    sql.split("CREATE TABLE internal.private_capture_primary_dispatch (")[1]
      .split(");")[0];
  assert(
    table.includes(
      "PRIMARY KEY REFERENCES internal.ordinary_initial_evidence(scan_id) ON DELETE CASCADE",
    ),
  );
  assert(!table.includes("REFERENCES internal.ai_quota_reservations"));
  assert(!table.includes("REFERENCES internal.identification_invocations"));
  for (
    const invariant of [
      "primary_dispatch_fence_version INTEGER NOT NULL DEFAULT 0",
      "SET DEFAULT 1",
      "permit.dispatch_transaction=pg_current_xact_id()",
      "BEFORE INSERT OR UPDATE ON internal.ai_quota_reservations",
      "BEFORE INSERT ON internal.identification_invocations",
      "private_capture_dispatch_consumed",
      "pg_try_advisory_xact_lock",
      "internal.capture_source_admission_stops",
      "retired_at IS NOT NULL",
      "p_scan IN (original_analysis_id,request_id)",
      "FROM PUBLIC,anon,authenticated,service_role",
    ]
  ) {
    assert(sql.includes(invariant), invariant);
  }
  assert(!sql.includes("GRANT EXECUTE"));
});

Deno.test("private dispatch rejects stale isolation before classifying any writer", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261121092320_require_current_capture_dispatch_snapshot.sql",
      import.meta.url,
    ),
  );
  for (
    const signature of [
      "internal.lock_private_capture_dispatch(uuid,uuid)",
      "internal.guard_private_capture_quota_state()",
      "internal.guard_private_capture_invocation()",
    ]
  ) assert(sql.includes(signature));
  assert(sql.includes("analysis_history_current_snapshot_required"));
  assert(sql.includes("ERRCODE=''25000''"));
  assert(sql.includes("replace(definition,anchor,guard)"));
  assert(sql.includes("private_capture_snapshot_guard_drift"));
});

Deno.test("unbound refund exception changes only isolation and preserves every guard", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261121095704_preserve_unbound_quota_refund_isolation.sql",
      import.meta.url,
    ),
  );
  for (
    const invariant of [
      "TG_OP<>''UPDATE''",
      "OLD.state=''reserved'' AND NEW.state=''refunded''",
      "OLD.original_analysis_id IS NULL AND NEW.original_analysis_id IS NULL",
      "NEW.refund_count=OLD.refund_count+1",
      "to_jsonb(NEW)-ARRAY[''state'',''refunded_at'',''refund_count'',''updated_at'']",
      "IS NOT DISTINCT FROM (to_jsonb(OLD)",
      "private_capture_refund_snapshot_guard_drift",
      "replace(definition,anchor,replacement)",
    ]
  ) assert(sql.includes(invariant), invariant);
  assert(!sql.includes("RETURN NEW"));
  assert(!sql.includes("GRANT "));
});
