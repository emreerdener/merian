import { assertEquals } from "@std/assert";
import type { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

/** Synthetic transport metadata only; never dispatches HTTP or changes a gate. */
export async function evidenceDispatchFixture(db: Client) {
  const prior = (await db.queryObject<{ value: Record<string, unknown> }>(
    "SELECT jsonb_build_object('enabled',enabled,'approved_project',approved_project,'pending_request_id',pending_request_id,'pending_dispatch_id',pending_dispatch_id) value FROM internal.observation_evidence_worker_state WHERE singleton",
  )).rows[0].value;
  assertEquals(prior.enabled, false);
  assertEquals(prior.pending_request_id, null);
  assertEquals(
    (await db.queryObject<{ n: number }>(
      "SELECT count(*)::int n FROM vault.secrets WHERE name IN ('SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY')",
    )).rows[0].n,
    0,
  );
  const dispatch = crypto.randomUUID();
  const secrets: string[] = [];
  const restore = async () => {
    await db.queryArray(
      "UPDATE internal.observation_evidence_worker_state SET enabled=$1,approved_project=$2,pending_request_id=$3,pending_dispatch_id=$4 WHERE singleton",
      [
        prior.enabled,
        prior.approved_project,
        prior.pending_request_id,
        prior.pending_dispatch_id,
      ],
    );
    await db.queryArray("DELETE FROM vault.secrets WHERE id=ANY($1::uuid[])", [
      secrets,
    ]);
  };
  try {
    for (
      const [value, name] of [
        ["https://abcdefghijklmnopqrst.supabase.co", "SUPABASE_URL"],
        ["sb_secret_" + "a".repeat(30), "SUPABASE_SERVICE_ROLE_KEY"],
      ]
    ) {
      secrets.push(
        (await db.queryObject<{ id: string }>(
          "SELECT vault.create_secret($1,$2) id",
          [value, name],
        )).rows[0].id,
      );
    }
    await db.queryArray(
      "UPDATE internal.observation_evidence_worker_state SET enabled=TRUE,approved_project='abcdefghijklmnopqrst',pending_request_id=-370,pending_dispatch_id=$1 WHERE singleton",
      [dispatch],
    );
    return { dispatch, restore };
  } catch (error) {
    await restore();
    throw error;
  }
}
