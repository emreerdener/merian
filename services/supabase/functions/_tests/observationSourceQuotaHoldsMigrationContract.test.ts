import { assert } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008220335_hold_source_bound_generic_quota_cleanup.sql",
    import.meta.url,
  ),
);
Deno.test("source quota holds exclude generic finalization expiry and pruning while preserving deletion proof", () => {
  for (
    const name of [
      "public.finalize_ai_quota_reservation",
      "internal.refund_expired_ai_quota_reservations",
      "internal.prune_ai_quota_state",
      "internal.fail_observation_analysis",
      "public.retire_owned_observation_analysis_execution",
      "internal.erase_observation_analysis_intent",
    ]
  ) assert(sql.includes(name));
  assert(sql.includes("b.analysis_id=reservations.original_analysis_id"));
  assert(sql.includes("b.analysis_id=candidates.original_analysis_id"));
  assert(sql.includes("internal.finalize_ai_quota_reservation_core"));
  assert(
    sql.includes("OLD.invocation_id IS NULL AND OLD.provider_outcome IS NULL"),
  );
  assert(sql.includes("q.original_analysis_id=OLD.analysis_id"));
  assert(!/GRANT |cron\.(?:schedule|unschedule)/.test(sql));
});
