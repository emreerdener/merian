import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  applyFieldTripScanProgress,
  fetchFirstFieldTripAchievementProgress,
} from "./db.ts";

const userId = "00000000-0000-0000-0000-000000000001";
const scanId = "00000000-0000-0000-0000-000000000002";

Deno.test("achievement progress scopes the service RPC to the verified user", async () => {
  let capturedName = "";
  let capturedArgs: Record<string, unknown> = {};
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      capturedName = name;
      capturedArgs = args;
      return Promise.resolve({
        data: {
          kind: "standard_outing",
          completed_at: "2026-07-18T14:00:00Z",
          template_slug: "backyard_safari",
          challenge_id: null,
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  const progress = await fetchFirstFieldTripAchievementProgress(
    userId,
    supabase,
  );

  assertEquals(capturedName, "get_first_field_trip_achievement_progress");
  assertEquals(capturedArgs, { target_user_id: userId });
  assertEquals(progress?.template_slug, "backyard_safari");
});

Deno.test("apply progress reports newly unlocked only for the completing mutation", async () => {
  let achievementReads = 0;
  let standardMutations = 0;
  const achievement = {
    kind: "seasonal_challenge" as const,
    completed_at: "2026-07-18T14:00:00Z",
    template_slug: null,
    challenge_id: "00000000-0000-0000-0000-000000000003",
  };
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      assertEquals(args.target_user_id ?? args.self_id, userId);
      switch (name) {
        case "get_first_field_trip_achievement_progress":
          achievementReads += 1;
          return Promise.resolve({
            data: achievementReads === 1 ? null : achievement,
            error: null,
          });
        case "apply_field_trip_scan_progress":
          standardMutations += 1;
          assertEquals(args.target_scan_id, scanId);
          return Promise.resolve({
            data: standardMutations === 1 ? [{ is_complete: true }] : [],
            error: null,
          });
        case "apply_field_trip_challenge_scan_progress":
          return Promise.resolve({ data: [], error: null });
        default:
          throw new Error(`Unexpected RPC ${name}`);
      }
    },
  } as unknown as SupabaseClient;

  const first = await applyFieldTripScanProgress(userId, scanId, supabase);
  const second = await applyFieldTripScanProgress(userId, scanId, supabase);

  assertEquals(first.firstFieldTripAchievement, achievement);
  assertEquals(first.firstFieldTripAchievementNewlyUnlocked, true);
  assertEquals(second.firstFieldTripAchievement, achievement);
  assertEquals(second.firstFieldTripAchievementNewlyUnlocked, false);
});
