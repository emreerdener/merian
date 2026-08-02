import { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals, assertRejects } from "@std/assert";
import { fetchCommunityIdentificationActivity } from "./db.ts";

Deno.test("Community Identify activity forwards filters and deterministic cursor", async () => {
  let capturedName = "";
  let capturedArgs: Record<string, unknown> = {};
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      capturedName = name;
      capturedArgs = args;
      return Promise.resolve({
        data: [{
          activity_id: "00000000-0000-4000-8000-000000000010",
          activity_type: "resolved",
          request_id: "00000000-0000-4000-8000-000000000011",
          post_id: "00000000-0000-4000-8000-000000000012",
          scan_id: "00000000-0000-4000-8000-000000000013",
          activity_at: "2026-07-30T20:00:00.000Z",
          suggestion_count: 0,
          recent_actor_names: [],
          request_group: "birds",
        }],
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  const rows = await fetchCommunityIdentificationActivity(
    "00000000-0000-4000-8000-000000000001",
    "mine",
    "birds",
    10,
    {
      beforeActivityAt: "2026-07-30T19:00:00.000Z",
      beforeActivityId: "00000000-0000-4000-8000-000000000002",
    },
    supabase,
  );

  assertEquals(capturedName, "get_community_identification_activity");
  assertEquals(capturedArgs, {
    self_id: "00000000-0000-4000-8000-000000000001",
    max_limit: 10,
    before_activity_at: "2026-07-30T19:00:00.000Z",
    before_activity_id: "00000000-0000-4000-8000-000000000002",
    request_scope: "mine",
    request_group_filter: "birds",
  });
  assertEquals(rows.length, 1);
  assertEquals(rows[0].activity_type, "resolved");
});

Deno.test("Community Identify activity surfaces RPC failures", async () => {
  const supabase = {
    rpc: () =>
      Promise.resolve({
        data: null,
        error: { message: "projection unavailable" },
      }),
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      fetchCommunityIdentificationActivity(
        "00000000-0000-4000-8000-000000000001",
        "all",
        "all",
        30,
        { beforeActivityAt: null, beforeActivityId: null },
        supabase,
      ),
    Error,
    "Failed to fetch community identification activity: projection unavailable",
  );
});
