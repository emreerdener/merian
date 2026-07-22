export const FIELD_TRIP_ACTIONS = [
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

export type FieldTripAction = (typeof FIELD_TRIP_ACTIONS)[number];

const fieldTripActionSet = new Set<string>(FIELD_TRIP_ACTIONS);

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export function normalizeFieldTripAction(rawAction: unknown): FieldTripAction {
  if (typeof rawAction !== "string") {
    throw makeHttpError(400, "action must be a string.");
  }

  if (fieldTripActionSet.has(rawAction)) {
    return rawAction as FieldTripAction;
  }

  console.warn("field_trip_action_rejected", {
    action: rawAction.slice(0, 64),
  });
  throw makeHttpError(400, "Unsupported field trip action.");
}
