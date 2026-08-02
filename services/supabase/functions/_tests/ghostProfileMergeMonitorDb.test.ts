import { assert } from "@std/assert";
import { inspectGhostMergeHealth } from "../../scripts/monitor_ghost_profile_merges.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");

Deno.test({
  name: "Ghost merge health SQL executes against the disposable catalog",
  ignore: databaseUrl == null,
  fn: async () => {
    const health = await inspectGhostMergeHealth(databaseUrl!, 20);

    assert(Number.isFinite(Date.parse(health.generated_at)));
    assert(health.recent_prepared_count >= 0);
    assert(health.cleanup_pending_count >= 0);
    assert(health.missing_destination_queue_count >= 0);
  },
});
