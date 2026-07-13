import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { upsertExplorePostReport } from "./db.ts";

Deno.test("repeat Explore post reports preserve the moderation status", async () => {
  let payload: Record<string, unknown> | undefined;
  let options: Record<string, unknown> | undefined;
  const supabase = {
    from(table: string) {
      assertEquals(table, "explore_post_reports");
      return {
        upsert(
          values: Record<string, unknown>,
          upsertOptions: Record<string, unknown>,
        ) {
          payload = values;
          options = upsertOptions;
          return Promise.resolve({ error: null });
        },
      };
    },
  } as unknown as SupabaseClient;

  await upsertExplorePostReport({
    postId: "00000000-0000-0000-0000-000000000001",
    reporterUserId: "00000000-0000-0000-0000-000000000002",
    postAuthorUserId: "00000000-0000-0000-0000-000000000003",
    reason: "Spam",
    details: "Repeated report",
  }, supabase);

  assertEquals(payload?.status, undefined);
  assertEquals(payload?.reason, "Spam");
  assertEquals(options, {
    onConflict: "post_id,reporter_user_id",
    ignoreDuplicates: false,
  });
});
