import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260731050009_add_community_identification_activity.sql",
  import.meta.url,
);
const usernameMigrationUrl = new URL(
  "../../migrations/20260801145720_use_usernames_for_community_identification_activity.sql",
  import.meta.url,
);
const edgeDbUrl = new URL(
  "../get-community-identification-activity/db.ts",
  import.meta.url,
);
const edgeIndexUrl = new URL(
  "../get-community-identification-activity/index.ts",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/\s+/g, " ").trim();
}

Deno.test("Community Identify activity projection is internal, RLS-enabled, and service-only", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.community_identification_activity_groups",
      "CREATE TABLE internal.community_identification_activity_actors",
      "ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.community_identification_activity_groups, internal.community_identification_activity_actors FROM PUBLIC, anon, authenticated",
      "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE internal.community_identification_activity_groups, internal.community_identification_activity_actors TO service_role",
      "SECURITY INVOKER SET search_path = ''",
      "REVOKE ALL ON FUNCTION public.get_community_identification_activity",
      "FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.get_community_identification_activity",
      "TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Community Identify activity groups suggestions at the inclusive one-hour boundary", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "activity_group.activity_at >= ( p_suggested_at - INTERVAL '60 minutes' )",
      "ON CONFLICT (activity_group_id, user_id) DO UPDATE",
      "suggestion_count = activity_actor.suggestion_count + 1",
      "LIMIT 3",
      "CREATE TRIGGER trg_record_community_identification_suggestion_activity",
      "AFTER INSERT ON public.explore_identifications",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Community Identify activity keeps resolutions separate and folds submission consensus", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  const resolutionBranch = sql.indexOf(
    "IF p_new_status = 'resolved' AND p_previous_status IS DISTINCT FROM p_new_status",
  );
  const submissionFold = sql.indexOf(
    "IF p_reason = 'identification_submitted'",
    resolutionBranch,
  );
  assert(resolutionBranch >= 0, "Missing immutable resolution branch.");
  assert(
    submissionFold > resolutionBranch,
    "Resolution must be recorded before submission consensus can be folded.",
  );

  for (
    const fragment of [
      "'resolved', p_created_at, p_created_at",
      "'consensus_changed', p_created_at, p_created_at",
      "activity_group.burst_started_at <= p_created_at",
      "source_consensus_event_id",
      "CREATE TRIGGER trg_record_community_consensus_activity",
      "AFTER INSERT ON public.community_consensus_events",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Community Identify activity backfills only the current request generation", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  assertStringIncludes(
    sql,
    "identification.created_at >= community_request.requested_at",
  );
  assertStringIncludes(
    sql,
    "consensus_event.created_at >= community_request.requested_at",
  );
  assertStringIncludes(
    sql,
    "community_request.requested_at = activity_group.request_generation_at",
  );
});

Deno.test("Community Identify activity read applies shared filters, visibility, and stable cursor ordering", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.community_identification_request_group",
      "ancestor.path OPERATOR(public.@>) selected_taxon.path",
      "CREATE OR REPLACE FUNCTION public.get_community_identification_feed",
      "public.community_identification_request_group( COALESCE( community_request.current_community_taxon_node_id, community_request.initial_taxon_node_id ) ) AS request_group",
      "public.community_identification_request_group(filter_taxon.id) AS request_group",
      "community_request.withdrawn_at IS NULL",
      "explore_post.unshared_at IS NULL",
      "explore_post.moderated_at IS NULL",
      "explore_post.media_health_status <> 'quarantined'",
      "scan.is_tombstoned = FALSE",
      "request_owner.is_shadowbanned = FALSE",
      "visible_media.health_status <> 'missing'",
      "request_scope = 'mine' AND community_request.requested_by = self_id",
      "request_group = request_group_filter",
      "activity_group.activity_at < before_activity_at",
      "activity_group.activity_at = before_activity_at AND activity_group.id < before_activity_id",
      "ORDER BY activity_at DESC, activity_id DESC",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("Community Identify activity attributes suggestions by public username", async () => {
  const sql = compact(await Deno.readTextFile(usernameMigrationUrl));

  assertStringIncludes(
    sql,
    "actor_user.public_username AS actor_username",
  );
  assert(
    !sql.includes("actor_user.public_author_name"),
    "Activity attribution must not expose profile/display names.",
  );
  assertStringIncludes(sql, "SECURITY INVOKER SET search_path = ''");
  assertStringIncludes(
    sql,
    "REVOKE ALL ON FUNCTION public.get_community_identification_activity",
  );
  assertStringIncludes(sql, "TO service_role");
});

Deno.test("Community Identify activity Edge function validates paired cursors and calls only its RPC", async () => {
  const [dbSource, indexSource] = await Promise.all([
    Deno.readTextFile(edgeDbUrl),
    Deno.readTextFile(edgeIndexUrl),
  ]);

  assertStringIncludes(dbSource, '"get_community_identification_activity"');
  assert(
    !dbSource.includes(".from("),
    "Activity Edge DB code must access the service-only projection through its RPC.",
  );
  assertStringIncludes(indexSource, "before_activity_at");
  assertStringIncludes(indexSource, "before_activity_id");
  assertStringIncludes(indexSource, "must be provided together");
  assertStringIncludes(indexSource, "normalizeLimit(body.limit, 30, 100)");
});
