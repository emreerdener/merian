import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals } from "@std/assert";
import {
  applyFieldTripScanProgress,
  fetchFirstFieldTripAchievementProgress,
  resetFieldTrip,
  stopFieldTrip,
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
  const achievement = {
    kind: "seasonal_challenge" as const,
    completed_at: "2026-07-18T14:00:00Z",
    template_slug: null,
    challenge_id: "00000000-0000-0000-0000-000000000003",
  };
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      assertEquals(name, "apply_field_trip_scan_progress_atomic");
      assertEquals(args, {
        self_id: userId,
        target_scan_id: scanId,
        preferred_user_field_trip_id: null,
        preferred_item_id: null,
      });
      return Promise.resolve({
        data: {
          field_trip_updates: [{ is_complete: true }],
          challenge_updates: [],
          first_field_trip_achievement: achievement,
          first_field_trip_achievement_newly_unlocked: true,
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  const progress = await applyFieldTripScanProgress(
    userId,
    scanId,
    null,
    supabase,
  );

  assertEquals(progress.fieldTripUpdates, [{ is_complete: true }]);
  assertEquals(progress.challengeUpdates, []);
  assertEquals(progress.firstFieldTripAchievement, achievement);
  assertEquals(progress.firstFieldTripAchievementNewlyUnlocked, true);
});

Deno.test("stop scopes lifecycle RPCs to the caller and returns stopped detail", async () => {
  const userFieldTripId = "00000000-0000-0000-0000-000000000004";
  const templateId = "00000000-0000-0000-0000-000000000005";
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      switch (name) {
        case "stop_field_trip":
          return Promise.resolve({ data: templateId, error: null });
        case "get_field_trip_template_detail":
          return Promise.resolve({
            data: { template_id: templateId, active_progress: null },
            error: null,
          });
        case "get_stopped_field_trip_progress":
          return Promise.resolve({
            data: [{
              template_id: templateId,
              stopped_progress: {
                user_field_trip_id: userFieldTripId,
                stopped_at: "2026-07-19T15:00:00Z",
              },
              levels: [{ level_number: 1, items: [] }],
            }],
            error: null,
          });
        default:
          throw new Error(`Unexpected RPC ${name}`);
      }
    },
  } as unknown as SupabaseClient;

  const detail = await stopFieldTrip(userId, userFieldTripId, supabase) as {
    stopped_progress: { user_field_trip_id: string };
    levels: unknown[];
  };

  assertEquals(detail.stopped_progress.user_field_trip_id, userFieldTripId);
  assertEquals(detail.levels.length, 1);
  assertEquals(calls.find((call) => call.name === "stop_field_trip")?.args, {
    self_id: userId,
    target_user_field_trip_id: userFieldTripId,
  });
  assertEquals(
    calls.find((call) => call.name === "get_field_trip_template_detail")
      ?.args,
    {
      self_id: userId,
      target_template_id: templateId,
      target_slug: null,
    },
  );
});

Deno.test("reset scopes lifecycle RPCs to the caller and returns initial detail", async () => {
  const userFieldTripId = "00000000-0000-0000-0000-000000000006";
  const templateId = "00000000-0000-0000-0000-000000000007";
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      switch (name) {
        case "reset_field_trip":
          return Promise.resolve({ data: templateId, error: null });
        case "get_field_trip_template_detail":
          return Promise.resolve({
            data: {
              template_id: templateId,
              active_progress: null,
              levels: [{ level_number: 1, items: [] }],
            },
            error: null,
          });
        case "get_stopped_field_trip_progress":
          return Promise.resolve({ data: [], error: null });
        default:
          throw new Error(`Unexpected RPC ${name}`);
      }
    },
  } as unknown as SupabaseClient;

  const detail = await resetFieldTrip(userId, userFieldTripId, supabase) as {
    active_progress: null;
  };

  assertEquals(detail.active_progress, null);
  assertEquals(calls.find((call) => call.name === "reset_field_trip")?.args, {
    self_id: userId,
    target_user_field_trip_id: userFieldTripId,
  });
});
