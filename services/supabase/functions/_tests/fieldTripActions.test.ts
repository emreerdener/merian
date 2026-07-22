import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  FIELD_TRIP_ACTIONS,
  normalizeFieldTripAction,
} from "../field-trips/actions.ts";

const IOS_FIELD_TRIP_ACTIONS = [
  "catalog",
  "capture_context",
  "achievement_progress",
  "challenges_catalog",
  "template_detail",
  "start",
  "stop",
  "reset",
  "challenge_detail",
  "join_challenge",
  "community_publications",
  "recent_publications",
  "challenge_publications",
  "apply_scan_progress",
  "scan_contributions",
  "scan_challenge_hashtags",
  "profile_summaries",
  "set_pinned_publications",
  "publish",
  "publish_challenge_entry",
  "detail",
  "challenge_entry_detail",
  "set_like",
  "set_challenge_entry_like",
  "comments",
  "challenge_entry_comments",
  "create_comment",
  "create_challenge_entry_comment",
] as const;

Deno.test("Field trip action contract accepts every iOS action", () => {
  assertEquals(FIELD_TRIP_ACTIONS, IOS_FIELD_TRIP_ACTIONS);
  for (const action of IOS_FIELD_TRIP_ACTIONS) {
    assertEquals(normalizeFieldTripAction(action), action);
  }
});

Deno.test("Field trip action contract rejects missing and unknown actions", () => {
  assertThrows(
    () => normalizeFieldTripAction(undefined),
    Error,
    "action must be a string.",
  );
  assertThrows(
    () => normalizeFieldTripAction("retired_action"),
    Error,
    "Unsupported field trip action.",
  );
});
