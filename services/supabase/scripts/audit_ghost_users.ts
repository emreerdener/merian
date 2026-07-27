/**
 * Read-only audit for Merian anonymous "ghost" users.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVER_API_KEY, SUPABASE_SECRET_KEYS, SUPABASE_SECRET_KEY,
 *   or legacy SUPABASE_SERVICE_ROLE_KEY
 *
 * Optional:
 *   MERIAN_GHOST_USER_ALLOWLIST=/path/to/allowlist.txt
 *
 * Example:
 *   deno run --allow-net --allow-env --allow-read --allow-write \
 *     services/supabase/scripts/audit_ghost_users.ts \
 *     --allowlist docs/internal/tester-user-allowlist.txt \
 *     --snapshot-json /tmp/merian-ghost-user-audit.json \
 *     --snapshot-csv /tmp/merian-ghost-user-audit.csv \
 *     --summary-md /tmp/merian-ghost-user-audit.md
 */

import { createServiceRoleClientFromEnvironment } from "../functions/_shared/serviceRoleClient.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

type UUID = string;

export type GhostUserClassification =
  | "real_account"
  | "active_ghost"
  | "likely_empty_ghost"
  | "public_profile_without_auth_user";

export type CleanupRecommendation =
  | "keep_real_account"
  | "keep_active_ghost"
  | "review_recent_empty_ghost"
  | "likely_empty_ghost_candidate_30d"
  | "review_public_profile_without_auth_user";

export interface AuditArgs {
  pageSize: number;
  allowlistPath: string | null;
  snapshotJsonPath: string | null;
  snapshotCsvPath: string | null;
  summaryMarkdownPath: string | null;
}

interface AuthUser {
  id: string;
  email?: string | null;
  created_at?: string | null;
  last_sign_in_at?: string | null;
  is_anonymous?: boolean | null;
  app_metadata?: Record<string, unknown> | null;
  user_metadata?: Record<string, unknown> | null;
  identities?: Array<Record<string, unknown>> | null;
}

interface PublicUserRow {
  id: string;
  email?: string | null;
  created_at?: string | null;
  subscription_tier?: string | null;
  subscription_expires_at?: string | null;
  public_author_name?: string | null;
  public_identity_source?: string | null;
  public_avatar_url?: string | null;
  public_username?: string | null;
  custom_avatar_url?: string | null;
  custom_avatar_updated_at?: string | null;
  current_streak_count?: number | null;
  total_species_discovered?: number | null;
}

interface ActivitySource {
  table: string;
  column: string;
  label: string;
  optional?: boolean;
}

interface ProtectedGhostMergeSourceRow {
  ghost_user_id: string;
}

export interface ActivityCounts {
  total: number;
  bySource: Record<string, number>;
}

export interface PublicIdentityFlags {
  hasCustomDisplayName: boolean;
  hasCustomAuthorName: boolean;
  hasNonAliasIdentitySource: boolean;
  hasCustomAvatar: boolean;
  publicUsername: string | null;
  defaultPublicUsername: string | null;
  usernameCheckStatus: "matched_default" | "custom" | "missing" | "unknown";
  hasCustomPublicIdentity: boolean;
}

export interface AuditSnapshotRow {
  user_id: string;
  classification: GhostUserClassification;
  cleanup_recommendation: CleanupRecommendation;
  allowlisted: boolean;
  age_days: number | null;
  age_bucket: string;
  auth: {
    exists: boolean;
    created_at: string | null;
    last_sign_in_at: string | null;
    email: string | null;
    is_anonymous: boolean | null;
    providers: string[];
  };
  public_user: {
    exists: boolean;
    created_at: string | null;
    email: string | null;
    subscription_tier: string | null;
    subscription_expires_at: string | null;
    public_identity_source: string | null;
    public_author_name: string | null;
    public_username: string | null;
    custom_avatar_url: string | null;
  };
  identity_flags: PublicIdentityFlags;
  activity: ActivityCounts;
}

export interface AuditSummary {
  generated_at: string;
  counts: Record<string, number>;
  missing_optional_sources: string[];
  recommendations: Record<CleanupRecommendation, number>;
}

export interface GhostUserAuditReport {
  summary: AuditSummary;
  rows: AuditSnapshotRow[];
}

const PUBLIC_USER_SELECT = [
  "id",
  "email",
  "created_at",
  "subscription_tier",
  "subscription_expires_at",
  "public_author_name",
  "public_identity_source",
  "public_avatar_url",
  "public_username",
  "custom_avatar_url",
  "custom_avatar_updated_at",
  "current_streak_count",
  "total_species_discovered",
].join(",");

const ACTIVITY_SOURCES: ActivitySource[] = [
  { table: "scans", column: "user_id", label: "scans" },
  {
    table: "collections",
    column: "user_id",
    label: "collections",
    optional: true,
  },
  {
    table: "export_jobs",
    column: "user_id",
    label: "export_jobs",
    optional: true,
  },
  {
    table: "failed_scan_ingestions",
    column: "user_id",
    label: "failed_scan_ingestions",
    optional: true,
  },
  {
    table: "scan_media_assets",
    column: "user_id",
    label: "scan_media_assets",
    optional: true,
  },
  {
    table: "user_species_preferences",
    column: "user_id",
    label: "user_species_preferences",
    optional: true,
  },
  {
    table: "user_push_devices",
    column: "user_id",
    label: "user_push_devices",
    optional: true,
  },
  { table: "user_blocks", column: "blocker_id", label: "user_blocks_blocker" },
  { table: "user_blocks", column: "blocked_id", label: "user_blocks_blocked" },
  {
    table: "user_follows",
    column: "follower_user_id",
    label: "user_follows_follower",
    optional: true,
  },
  {
    table: "user_follows",
    column: "followee_user_id",
    label: "user_follows_followee",
    optional: true,
  },
  {
    table: "explore_posts",
    column: "user_id",
    label: "explore_posts",
    optional: true,
  },
  {
    table: "explore_post_likes",
    column: "user_id",
    label: "explore_post_likes",
    optional: true,
  },
  {
    table: "explore_post_comments",
    column: "user_id",
    label: "explore_post_comments",
    optional: true,
  },
  {
    table: "explore_comment_reactions",
    column: "user_id",
    label: "explore_comment_reactions",
    optional: true,
  },
  {
    table: "explore_comment_mentions",
    column: "mentioned_user_id",
    label: "explore_comment_mentions",
    optional: true,
  },
  {
    table: "explore_comment_reports",
    column: "reporter_user_id",
    label: "explore_comment_reports_reporter",
    optional: true,
  },
  {
    table: "explore_comment_reports",
    column: "comment_author_user_id",
    label: "explore_comment_reports_author",
    optional: true,
  },
  {
    table: "explore_post_notifications",
    column: "user_id",
    label: "explore_notifications_recipient",
    optional: true,
  },
  {
    table: "explore_post_notifications",
    column: "triggering_user_id",
    label: "explore_notifications_actor",
    optional: true,
  },
  {
    table: "explore_community_requests",
    column: "requested_by",
    label: "community_requests",
    optional: true,
  },
  {
    table: "explore_identifications",
    column: "user_id",
    label: "community_identifications",
    optional: true,
  },
  {
    table: "community_feedback",
    column: "user_id",
    label: "community_feedback",
    optional: true,
  },
  {
    table: "feedback_survey_responses",
    column: "user_id",
    label: "feedback_survey_responses",
    optional: true,
  },
  {
    table: "insight_chat_conversations",
    column: "user_id",
    label: "insight_chat_conversations",
    optional: true,
  },
  {
    table: "insight_chat_messages",
    column: "user_id",
    label: "insight_chat_messages",
    optional: true,
  },
  {
    table: "insight_chat_message_feedback",
    column: "user_id",
    label: "insight_chat_message_feedback",
    optional: true,
  },
  {
    table: "insight_chat_feature_feedback",
    column: "user_id",
    label: "insight_chat_feature_feedback",
    optional: true,
  },
  {
    table: "user_field_trips",
    column: "user_id",
    label: "user_field_trips",
    optional: true,
  },
  {
    table: "field_trip_publications",
    column: "user_id",
    label: "field_trip_publications",
    optional: true,
  },
  {
    table: "field_trip_publication_likes",
    column: "user_id",
    label: "field_trip_publication_likes",
    optional: true,
  },
  {
    table: "field_trip_publication_comments",
    column: "user_id",
    label: "field_trip_publication_comments",
    optional: true,
  },
  {
    table: "field_trip_activity_notifications",
    column: "user_id",
    label: "field_trip_activity_recipient",
    optional: true,
  },
  {
    table: "field_trip_activity_notifications",
    column: "actor_user_id",
    label: "field_trip_activity_actor",
    optional: true,
  },
  {
    table: "field_trip_challenge_participants",
    column: "user_id",
    label: "field_trip_challenge_participants",
    optional: true,
  },
  {
    table: "field_trip_challenge_badges",
    column: "user_id",
    label: "field_trip_challenge_badges",
    optional: true,
  },
  {
    table: "field_trip_challenge_entries",
    column: "user_id",
    label: "field_trip_challenge_entries",
    optional: true,
  },
  {
    table: "field_trip_challenge_entry_likes",
    column: "user_id",
    label: "field_trip_challenge_entry_likes",
    optional: true,
  },
  {
    table: "field_trip_challenge_entry_comments",
    column: "user_id",
    label: "field_trip_challenge_entry_comments",
    optional: true,
  },
  {
    table: "flagged_reviews",
    column: "user_id",
    label: "flagged_reviews",
    optional: true,
  },
];

if (import.meta.main) {
  const exitCode = await runAudit(Deno.args);
  Deno.exit(exitCode);
}

export async function runAudit(rawArgs: string[]): Promise<number> {
  const args = parseAuditArgs(rawArgs);
  const supabase = createServiceRoleClientFromEnvironment();
  const allowlist = await loadAllowlist(args.allowlistPath);

  const authUsers = await fetchAuthUsers(
    supabase,
    args.pageSize,
  );
  const publicUsers = await fetchPublicUsers(
    supabase,
    args.pageSize,
  );
  const activityResult = await fetchActivityCounts(
    supabase,
    args.pageSize,
  );
  const protectedMergeSources = await fetchProtectedGhostMergeSources(
    supabase,
  );
  addProtectedGhostMergeActivity(
    activityResult.activityByUserId,
    protectedMergeSources,
  );
  const defaultUsernameResolver = makeDefaultUsernameResolver(
    supabase,
  );
  const report = await buildAuditReport({
    authUsers,
    publicUsers,
    allowlist,
    activityByUserId: activityResult.activityByUserId,
    missingOptionalSources: activityResult.missingOptionalSources,
    defaultUsernameResolver,
    now: new Date(),
  });

  printSummary(report.summary);
  await writeOutputs(report, args);
  return 0;
}

export async function buildAuditReport(input: {
  authUsers: AuthUser[];
  publicUsers: PublicUserRow[];
  allowlist: Set<string>;
  activityByUserId: Map<string, ActivityCounts>;
  missingOptionalSources: string[];
  defaultUsernameResolver: (userId: string) => Promise<string | null>;
  now: Date;
}): Promise<GhostUserAuditReport> {
  const authById = new Map(
    input.authUsers.map((user) => [normalizeId(user.id), user]),
  );
  const publicById = new Map(
    input.publicUsers.map((user) => [normalizeId(user.id), user]),
  );
  const userIds = new Set<UUID>([...authById.keys(), ...publicById.keys()]);
  const rows: AuditSnapshotRow[] = [];

  for (const userId of [...userIds].sort()) {
    rows.push(
      await buildSnapshotRow({
        userId,
        authUser: authById.get(userId) ?? null,
        publicUser: publicById.get(userId) ?? null,
        allowlist: input.allowlist,
        activityCounts: input.activityByUserId.get(userId) ??
          emptyActivityCounts(),
        defaultUsernameResolver: input.defaultUsernameResolver,
        now: input.now,
      }),
    );
  }

  return {
    summary: buildSummary(rows, input.missingOptionalSources, input.now),
    rows,
  };
}

export async function buildSnapshotRow(input: {
  userId: string;
  authUser: AuthUser | null;
  publicUser: PublicUserRow | null;
  allowlist: Set<string>;
  activityCounts: ActivityCounts;
  defaultUsernameResolver: (userId: string) => Promise<string | null>;
  now: Date;
}): Promise<AuditSnapshotRow> {
  const email = normalizedText(input.authUser?.email) ??
    normalizedText(input.publicUser?.email);
  const providers = providerSummary(input.authUser);
  const allowlisted = input.allowlist.has(input.userId) ||
    (email ? input.allowlist.has(email.toLowerCase()) : false);
  const identityFlags = await publicIdentityFlags(
    input.userId,
    input.publicUser,
    input.defaultUsernameResolver,
  );
  const createdAt = input.authUser?.created_at ??
    input.publicUser?.created_at ?? null;
  const ageDays = ageInDays(createdAt, input.now);
  const classification = classifyAuditRow({
    authExists: !!input.authUser,
    isAnonymous: input.authUser?.is_anonymous ?? null,
    email,
    providers,
    allowlisted,
    publicUser: input.publicUser,
    identityFlags,
    activityCounts: input.activityCounts,
  });

  return {
    user_id: input.userId,
    classification,
    cleanup_recommendation: recommendationFor(classification, ageDays),
    allowlisted,
    age_days: ageDays,
    age_bucket: ageBucket(ageDays),
    auth: {
      exists: !!input.authUser,
      created_at: input.authUser?.created_at ?? null,
      last_sign_in_at: input.authUser?.last_sign_in_at ?? null,
      email,
      is_anonymous: input.authUser?.is_anonymous ?? null,
      providers,
    },
    public_user: {
      exists: !!input.publicUser,
      created_at: input.publicUser?.created_at ?? null,
      email: normalizedText(input.publicUser?.email),
      subscription_tier: normalizedText(input.publicUser?.subscription_tier),
      subscription_expires_at: normalizedText(
        input.publicUser?.subscription_expires_at,
      ),
      public_identity_source: normalizedText(
        input.publicUser?.public_identity_source,
      ),
      public_author_name: normalizedText(input.publicUser?.public_author_name),
      public_username: normalizedText(input.publicUser?.public_username),
      custom_avatar_url: normalizedText(input.publicUser?.custom_avatar_url),
    },
    identity_flags: identityFlags,
    activity: input.activityCounts,
  };
}

export function classifyAuditRow(input: {
  authExists: boolean;
  isAnonymous: boolean | null;
  email: string | null;
  providers: string[];
  allowlisted: boolean;
  publicUser: PublicUserRow | null;
  identityFlags: PublicIdentityFlags;
  activityCounts: ActivityCounts;
}): GhostUserClassification {
  if (!input.authExists) {
    return "public_profile_without_auth_user";
  }

  if (
    input.allowlisted ||
    input.isAnonymous === false ||
    !!input.email ||
    input.providers.some((provider) => provider !== "anonymous") ||
    hasPaidOrPassState(input.publicUser)
  ) {
    return "real_account";
  }

  if (
    input.isAnonymous === true &&
    input.activityCounts.total === 0 &&
    !input.identityFlags.hasCustomPublicIdentity
  ) {
    return "likely_empty_ghost";
  }

  return "active_ghost";
}

export function recommendationFor(
  classification: GhostUserClassification,
  ageDays: number | null,
): CleanupRecommendation {
  switch (classification) {
    case "real_account":
      return "keep_real_account";
    case "active_ghost":
      return "keep_active_ghost";
    case "public_profile_without_auth_user":
      return "review_public_profile_without_auth_user";
    case "likely_empty_ghost":
      return ageDays != null && ageDays >= 30
        ? "likely_empty_ghost_candidate_30d"
        : "review_recent_empty_ghost";
  }
}

export async function publicIdentityFlags(
  userId: string,
  publicUser: PublicUserRow | null,
  defaultUsernameResolver: (userId: string) => Promise<string | null>,
): Promise<PublicIdentityFlags> {
  const publicUsername = normalizedText(publicUser?.public_username);
  const publicAuthorName = normalizedText(publicUser?.public_author_name);
  const publicIdentitySource = normalizedText(
    publicUser?.public_identity_source,
  );
  const hasCustomDisplayName = publicIdentitySource === "display_name";
  const hasNonAliasIdentitySource = publicIdentitySource !== null &&
    publicIdentitySource !== "alias";
  const hasCustomAuthorName = publicAuthorName !== null &&
    publicAuthorName !== publicUsername;
  const hasCustomAvatar = !!normalizedText(publicUser?.custom_avatar_url);
  let defaultPublicUsername: string | null = null;
  let usernameCheckStatus: PublicIdentityFlags["usernameCheckStatus"] =
    publicUsername ? "unknown" : "missing";

  if (publicUsername) {
    try {
      defaultPublicUsername = await defaultUsernameResolver(userId);
      if (defaultPublicUsername) {
        usernameCheckStatus = publicUsername === defaultPublicUsername
          ? "matched_default"
          : "custom";
      }
    } catch (error) {
      console.warn(
        `default username lookup failed for ${userId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  return {
    hasCustomDisplayName,
    hasCustomAuthorName,
    hasNonAliasIdentitySource,
    hasCustomAvatar,
    publicUsername,
    defaultPublicUsername,
    usernameCheckStatus,
    hasCustomPublicIdentity: hasCustomDisplayName ||
      hasCustomAuthorName ||
      hasNonAliasIdentitySource ||
      hasCustomAvatar ||
      usernameCheckStatus === "custom" ||
      usernameCheckStatus === "unknown",
  };
}

function hasPaidOrPassState(publicUser: PublicUserRow | null): boolean {
  if (!publicUser) return false;
  if (publicUser.subscription_tier === "pro") return true;
  const expiresAt = normalizedText(publicUser.subscription_expires_at);
  return !!expiresAt && Date.parse(expiresAt) > Date.now();
}

async function fetchAuthUsers(
  supabase: SupabaseClient,
  pageSize: number,
): Promise<AuthUser[]> {
  const users: AuthUser[] = [];
  let page = 1;

  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({
      page: page,
      perPage: pageSize,
    });

    if (error) {
      throw new Error(
        `Failed to fetch auth users: ${error.message} (Code: ${error.status})`,
      );
    }

    const pageUsers = data.users as AuthUser[];
    users.push(...pageUsers);
    if (pageUsers.length < pageSize) break;
    page += 1;
  }

  return users;
}

async function fetchPublicUsers(
  supabase: SupabaseClient,
  pageSize: number,
): Promise<PublicUserRow[]> {
  const rows: PublicUserRow[] = [];
  let offset = 0;

  while (true) {
    const { data, error } = await supabase
      .from("users")
      .select(PUBLIC_USER_SELECT)
      .order("created_at", { ascending: true })
      .range(offset, offset + pageSize - 1);

    if (error) {
      throw new Error(`Failed to fetch public users: ${error.message}`);
    }

    const pageRows = data as unknown as PublicUserRow[];
    rows.push(...pageRows);
    if (pageRows.length < pageSize) break;
    offset += pageSize;
  }

  return rows;
}

async function fetchActivityCounts(
  supabase: SupabaseClient,
  pageSize: number,
): Promise<{
  activityByUserId: Map<string, ActivityCounts>;
  missingOptionalSources: string[];
}> {
  const activityByUserId = new Map<string, ActivityCounts>();
  const missingOptionalSources: string[] = [];

  for (const source of ACTIVITY_SOURCES) {
    try {
      const values = await fetchColumnValues(
        supabase,
        source,
        pageSize,
      );
      for (const value of values) {
        const userId = normalizeId(value);
        const counts = activityByUserId.get(userId) ?? emptyActivityCounts();
        counts.total += 1;
        counts.bySource[source.label] = (counts.bySource[source.label] ?? 0) +
          1;
        activityByUserId.set(userId, counts);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (source.optional) {
        missingOptionalSources.push(`${source.table}.${source.column}`);
        console.warn(
          `Skipping optional audit source ${source.table}.${source.column}: ${message}`,
        );
        continue;
      }
      throw error;
    }
  }

  return { activityByUserId, missingOptionalSources };
}

async function fetchProtectedGhostMergeSources(
  supabase: SupabaseClient,
): Promise<string[]> {
  const { data, error } = await supabase.rpc(
    "list_protected_ghost_profile_merge_sources",
  );

  if (error) {
    throw new Error(
      `protected ghost-merge source lookup returned HTTP ${error.code}: ${error.message}`,
    );
  }

  const rows = data as ProtectedGhostMergeSourceRow[];
  return rows
    .map((row) => row.ghost_user_id)
    .filter((value): value is string =>
      typeof value === "string" && value.trim() !== ""
    );
}

export function addProtectedGhostMergeActivity(
  activityByUserId: Map<string, ActivityCounts>,
  protectedUserIds: string[],
): void {
  for (const rawUserId of new Set(protectedUserIds.map(normalizeId))) {
    const counts = activityByUserId.get(rawUserId) ?? emptyActivityCounts();
    counts.total += 1;
    counts.bySource.ghost_profile_merge_handoff =
      (counts.bySource.ghost_profile_merge_handoff ?? 0) + 1;
    activityByUserId.set(rawUserId, counts);
  }
}

async function fetchColumnValues(
  supabase: SupabaseClient,
  source: ActivitySource,
  pageSize: number,
): Promise<string[]> {
  const values: string[] = [];
  let offset = 0;

  while (true) {
    const { data, error } = await supabase
      .from(source.table)
      .select(source.column)
      .range(offset, offset + pageSize - 1);

    if (error) {
      throw new Error(
        `Failed to fetch column ${source.column} from ${source.table}: ${error.message}`,
      );
    }

    const rows = data as unknown as Array<Record<string, unknown>>;
    for (const row of rows) {
      const value = row[source.column];
      if (typeof value === "string" && value.trim() !== "") {
        values.push(value);
      }
    }

    if (rows.length < pageSize) break;
    offset += pageSize;
  }

  return values;
}

function makeDefaultUsernameResolver(
  supabase: SupabaseClient,
): (userId: string) => Promise<string | null> {
  return async (userId: string) => {
    const { data, error } = await supabase.rpc(
      "build_default_public_username",
      { target_user_id: userId },
    );
    if (error) {
      throw new Error(`RPC Error: ${error.message}`);
    }
    return typeof data === "string" ? data : null;
  };
}

async function loadAllowlist(path: string | null): Promise<Set<string>> {
  const resolvedPath = path ?? Deno.env.get("MERIAN_GHOST_USER_ALLOWLIST") ??
    null;
  if (!resolvedPath) return new Set();

  const text = await Deno.readTextFile(resolvedPath);
  return new Set(
    text.split(/\r?\n/)
      .map((line) => line.replace(/#.*/, "").trim().toLowerCase())
      .filter((line) => line.length > 0),
  );
}

function buildSummary(
  rows: AuditSnapshotRow[],
  missingOptionalSources: string[],
  now: Date,
): AuditSummary {
  const counts: Record<string, number> = {
    total_rows: rows.length,
  };
  const recommendations = {} as Record<CleanupRecommendation, number>;

  for (const row of rows) {
    counts[row.classification] = (counts[row.classification] ?? 0) + 1;
    counts[`age_${row.age_bucket}`] = (counts[`age_${row.age_bucket}`] ?? 0) +
      1;
    recommendations[row.cleanup_recommendation] =
      (recommendations[row.cleanup_recommendation] ?? 0) + 1;
  }

  return {
    generated_at: now.toISOString(),
    counts,
    missing_optional_sources: missingOptionalSources,
    recommendations,
  };
}

async function writeOutputs(
  report: GhostUserAuditReport,
  args: AuditArgs,
): Promise<void> {
  if (args.snapshotJsonPath) {
    await Deno.writeTextFile(
      args.snapshotJsonPath,
      `${JSON.stringify(report, null, 2)}\n`,
    );
    console.log(`snapshot_json: ${args.snapshotJsonPath}`);
  }

  if (args.snapshotCsvPath) {
    await Deno.writeTextFile(args.snapshotCsvPath, renderCsv(report.rows));
    console.log(`snapshot_csv: ${args.snapshotCsvPath}`);
  }

  if (args.summaryMarkdownPath) {
    await Deno.writeTextFile(args.summaryMarkdownPath, renderMarkdown(report));
    console.log(`summary_markdown: ${args.summaryMarkdownPath}`);
  }
}

function printSummary(summary: AuditSummary): void {
  console.log("Ghost user audit complete");
  for (const [key, value] of Object.entries(summary.counts).sort()) {
    console.log(`${key}: ${value}`);
  }
  for (const [key, value] of Object.entries(summary.recommendations).sort()) {
    console.log(`${key}: ${value}`);
  }
  if (summary.missing_optional_sources.length > 0) {
    console.warn(
      `missing_optional_sources: ${
        summary.missing_optional_sources.join(", ")
      }`,
    );
  }
}

export function renderMarkdown(report: GhostUserAuditReport): string {
  const lines = [
    "# Merian Ghost User Audit",
    "",
    `Generated: ${report.summary.generated_at}`,
    "",
    "## Counts",
    "",
    ...Object.entries(report.summary.counts)
      .sort()
      .map(([key, value]) => `- ${key}: \`${value}\``),
    "",
    "## Recommendations",
    "",
    ...Object.entries(report.summary.recommendations)
      .sort()
      .map(([key, value]) => `- ${key}: \`${value}\``),
    "",
    "## Missing Optional Sources",
    "",
  ];

  if (report.summary.missing_optional_sources.length === 0) {
    lines.push("- None");
  } else {
    for (const source of report.summary.missing_optional_sources) {
      lines.push(`- ${source}`);
    }
  }

  lines.push(
    "",
    "## Candidate Sample",
    "",
    ...report.rows
      .filter((row) =>
        row.cleanup_recommendation === "likely_empty_ghost_candidate_30d"
      )
      .slice(0, 20)
      .map((row) =>
        `- ${row.user_id} age=${row.age_days ?? "unknown"}d last_sign_in=${
          row.auth.last_sign_in_at ?? "unknown"
        }`
      ),
    "",
  );

  return `${lines.join("\n")}\n`;
}

export function renderCsv(rows: AuditSnapshotRow[]): string {
  const columns = [
    "user_id",
    "classification",
    "cleanup_recommendation",
    "allowlisted",
    "age_days",
    "age_bucket",
    "auth_exists",
    "auth_created_at",
    "auth_last_sign_in_at",
    "auth_email",
    "auth_is_anonymous",
    "auth_providers",
    "public_user_exists",
    "subscription_tier",
    "subscription_expires_at",
    "public_identity_source",
    "public_username",
    "default_public_username",
    "username_check_status",
    "has_custom_public_identity",
    "activity_total",
    "activity_by_source",
  ];

  const body = rows.map((row) =>
    [
      row.user_id,
      row.classification,
      row.cleanup_recommendation,
      row.allowlisted,
      row.age_days ?? "",
      row.age_bucket,
      row.auth.exists,
      row.auth.created_at ?? "",
      row.auth.last_sign_in_at ?? "",
      row.auth.email ?? "",
      row.auth.is_anonymous ?? "",
      row.auth.providers.join("|"),
      row.public_user.exists,
      row.public_user.subscription_tier ?? "",
      row.public_user.subscription_expires_at ?? "",
      row.public_user.public_identity_source ?? "",
      row.identity_flags.publicUsername ?? "",
      row.identity_flags.defaultPublicUsername ?? "",
      row.identity_flags.usernameCheckStatus,
      row.identity_flags.hasCustomPublicIdentity,
      row.activity.total,
      JSON.stringify(row.activity.bySource),
    ].map(csvCell).join(",")
  );

  return `${columns.join(",")}\n${body.join("\n")}\n`;
}

function parseAuditArgs(rawArgs: string[]): AuditArgs {
  const args: AuditArgs = {
    pageSize: 1000,
    allowlistPath: null,
    snapshotJsonPath: null,
    snapshotCsvPath: null,
    summaryMarkdownPath: null,
  };

  for (let index = 0; index < rawArgs.length; index += 1) {
    const arg = rawArgs[index];
    switch (arg) {
      case "--page-size":
        args.pageSize = parsePositiveInteger(
          readNextArg(rawArgs, ++index, arg),
          arg,
        );
        break;
      case "--allowlist":
        args.allowlistPath = readNextArg(rawArgs, ++index, arg);
        break;
      case "--snapshot-json":
        args.snapshotJsonPath = readNextArg(rawArgs, ++index, arg);
        break;
      case "--snapshot-csv":
        args.snapshotCsvPath = readNextArg(rawArgs, ++index, arg);
        break;
      case "--summary-md":
        args.summaryMarkdownPath = readNextArg(rawArgs, ++index, arg);
        break;
      case "--help":
        printHelpAndExit();
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return args;
}

function readNextArg(rawArgs: string[], index: number, flag: string): string {
  const value = rawArgs[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}

function parsePositiveInteger(value: string, flag: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${flag} must be a positive integer.`);
  }
  return parsed;
}

function printHelpAndExit(): never {
  console.log(
    `Usage: deno run --allow-net --allow-env --allow-read --allow-write services/supabase/scripts/audit_ghost_users.ts [options]

Required env:
  SUPABASE_URL
  SUPABASE_SERVER_API_KEY   Preferred explicit server key.
  SUPABASE_SECRET_KEYS      Platform-managed current secret-key dictionary.
  SUPABASE_SECRET_KEY       Current manually managed secret-key fallback.
  SUPABASE_SERVICE_ROLE_KEY Legacy fallback for older projects.

Options:
  --allowlist <path>       Text file of tester/dev user IDs or emails, one per line.
  --snapshot-json <path>   Write full JSON report.
  --snapshot-csv <path>    Write CSV snapshot.
  --summary-md <path>      Write Markdown summary.
  --page-size <number>     REST page size. Default: 1000.
`,
  );
  Deno.exit(0);
}

function providerSummary(authUser: AuthUser | null): string[] {
  if (!authUser) return [];
  const providers = new Set<string>();
  const appProvider = normalizedText(authUser.app_metadata?.provider);
  if (appProvider) providers.add(appProvider);
  for (const identity of authUser.identities ?? []) {
    const provider = normalizedText(identity.provider);
    if (provider) providers.add(provider);
  }
  if (authUser.is_anonymous === true && providers.size === 0) {
    providers.add("anonymous");
  }
  return [...providers].sort();
}

function emptyActivityCounts(): ActivityCounts {
  return { total: 0, bySource: {} };
}

function normalizedText(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

function normalizeId(value: string): string {
  return value.trim().toLowerCase();
}

function ageInDays(iso: string | null | undefined, now: Date): number | null {
  if (!iso) return null;
  const timestamp = Date.parse(iso);
  if (Number.isNaN(timestamp)) return null;
  return Math.max(0, Math.floor((now.getTime() - timestamp) / 86_400_000));
}

function ageBucket(ageDays: number | null): string {
  if (ageDays == null) return "unknown";
  if (ageDays < 7) return "lt_7d";
  if (ageDays < 14) return "7_13d";
  if (ageDays < 30) return "14_29d";
  if (ageDays < 90) return "30_89d";
  return "90d_plus";
}

function csvCell(value: unknown): string {
  const text = String(value);
  if (!/[",\n\r]/.test(text)) return text;
  return `"${text.replace(/"/g, '""')}"`;
}
