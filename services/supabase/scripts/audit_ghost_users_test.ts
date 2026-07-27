import {
  type ActivityCounts,
  addProtectedGhostMergeActivity,
  buildSnapshotRow,
  classifyAuditRow,
  type PublicIdentityFlags,
  publicIdentityFlags,
  recommendationFor,
  renderCsv,
  requiredAdminApiKey,
} from "./audit_ghost_users.ts";

const LEGACY_SERVICE_ROLE_KEY = [
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
  "eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUifQ",
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
].join(".");
const fakeCurrentSecretKey = (label: string) =>
  ["sb", "secret", label, "a".repeat(20)].join("_");
const CURRENT_SECRET_KEY = fakeCurrentSecretKey("current");
const EXPLICIT_SECRET_KEY = fakeCurrentSecretKey("explicit");
const DEFAULT_SECRET_KEY = fakeCurrentSecretKey("default");
const WORKER_SECRET_KEY = fakeCurrentSecretKey("worker");

Deno.test("protected ghost merge sources are never classified as empty", () => {
  const activityByUserId = new Map<string, ActivityCounts>();
  addProtectedGhostMergeActivity(activityByUserId, [
    "GHOST-PENDING",
    "ghost-pending",
  ]);

  const activity = activityByUserId.get("ghost-pending");
  assertEquals(activity?.total, 1);
  assertEquals(activity?.bySource.ghost_profile_merge_handoff, 1);
  assertEquals(
    classifyAuditRow({
      authExists: true,
      isAnonymous: true,
      email: null,
      providers: ["anonymous"],
      allowlisted: false,
      publicUser: {
        id: "ghost-pending",
        subscription_tier: "free",
      },
      identityFlags: defaultIdentityFlags(),
      activityCounts: activity ?? emptyActivity(),
    }),
    "active_ghost",
  );
});

Deno.test("classifyAuditRow keeps non-anonymous auth users as real accounts", () => {
  const classification = classifyAuditRow({
    authExists: true,
    isAnonymous: false,
    email: "tester@example.com",
    providers: ["google"],
    allowlisted: false,
    publicUser: {
      id: "user-1",
      subscription_tier: "free",
    },
    identityFlags: defaultIdentityFlags(),
    activityCounts: emptyActivity(),
  });

  assertEquals(classification, "real_account");
});

Deno.test("classifyAuditRow keeps anonymous users with activity as active ghosts", () => {
  const classification = classifyAuditRow({
    authExists: true,
    isAnonymous: true,
    email: null,
    providers: ["anonymous"],
    allowlisted: false,
    publicUser: {
      id: "ghost-1",
      subscription_tier: "free",
    },
    identityFlags: defaultIdentityFlags(),
    activityCounts: {
      total: 1,
      bySource: { scans: 1 },
    },
  });

  assertEquals(classification, "active_ghost");
});

Deno.test("classifyAuditRow keeps customized anonymous users as active ghosts", () => {
  const classification = classifyAuditRow({
    authExists: true,
    isAnonymous: true,
    email: null,
    providers: ["anonymous"],
    allowlisted: false,
    publicUser: {
      id: "ghost-2",
      subscription_tier: "free",
      public_identity_source: "display_name",
    },
    identityFlags: {
      ...defaultIdentityFlags(),
      hasCustomDisplayName: true,
      hasCustomPublicIdentity: true,
    },
    activityCounts: emptyActivity(),
  });

  assertEquals(classification, "active_ghost");
});

Deno.test("publicIdentityFlags treats derived identity sources as custom for safety", async () => {
  const flags = await publicIdentityFlags(
    "ghost-derived",
    {
      id: "ghost-derived",
      public_author_name: "River Tester",
      public_identity_source: "derived_name",
      public_username: "fern_grove_22",
    },
    () => Promise.resolve("fern_grove_22"),
  );

  assertEquals(flags.hasNonAliasIdentitySource, true);
  assertEquals(flags.hasCustomPublicIdentity, true);
});

Deno.test("publicIdentityFlags treats alias author-name drift as custom for safety", async () => {
  const flags = await publicIdentityFlags(
    "ghost-author-drift",
    {
      id: "ghost-author-drift",
      public_author_name: "River Tester",
      public_identity_source: "alias",
      public_username: "fern_grove_22",
    },
    () => Promise.resolve("fern_grove_22"),
  );

  assertEquals(flags.hasCustomAuthorName, true);
  assertEquals(flags.hasCustomPublicIdentity, true);
});

Deno.test("classifyAuditRow marks empty anonymous users as likely empty ghosts", () => {
  const classification = classifyAuditRow({
    authExists: true,
    isAnonymous: true,
    email: null,
    providers: ["anonymous"],
    allowlisted: false,
    publicUser: {
      id: "ghost-3",
      subscription_tier: "free",
    },
    identityFlags: defaultIdentityFlags(),
    activityCounts: emptyActivity(),
  });

  assertEquals(classification, "likely_empty_ghost");
});

Deno.test("classifyAuditRow isolates public profiles without auth users for manual review", () => {
  const classification = classifyAuditRow({
    authExists: false,
    isAnonymous: null,
    email: null,
    providers: [],
    allowlisted: false,
    publicUser: {
      id: "orphan-1",
      subscription_tier: "free",
    },
    identityFlags: defaultIdentityFlags(),
    activityCounts: emptyActivity(),
  });

  assertEquals(classification, "public_profile_without_auth_user");
});

Deno.test("recommendationFor only elevates empty ghosts after 30 days", () => {
  assertEquals(
    recommendationFor("likely_empty_ghost", 29),
    "review_recent_empty_ghost",
  );
  assertEquals(
    recommendationFor("likely_empty_ghost", 30),
    "likely_empty_ghost_candidate_30d",
  );
});

Deno.test("publicIdentityFlags treats unknown username default checks as custom for safety", async () => {
  const flags = await publicIdentityFlags(
    "ghost-4",
    {
      id: "ghost-4",
      public_username: "river_path_42",
      public_identity_source: "alias",
    },
    () => Promise.resolve(null),
  );

  assertEquals(flags.usernameCheckStatus, "unknown");
  assertEquals(flags.hasCustomPublicIdentity, true);
});

Deno.test("publicIdentityFlags accepts default usernames as non-custom", async () => {
  const flags = await publicIdentityFlags(
    "ghost-5",
    {
      id: "ghost-5",
      public_username: "moss_trail_11",
      public_identity_source: "alias",
    },
    () => Promise.resolve("moss_trail_11"),
  );

  assertEquals(flags.usernameCheckStatus, "matched_default");
  assertEquals(flags.hasCustomPublicIdentity, false);
});

Deno.test("buildSnapshotRow emits a 30-day empty ghost cleanup recommendation", async () => {
  const row = await buildSnapshotRow({
    userId: "ghost-6",
    authUser: {
      id: "ghost-6",
      is_anonymous: true,
      created_at: "2026-05-01T00:00:00.000Z",
    },
    publicUser: {
      id: "ghost-6",
      subscription_tier: "free",
      public_username: "fern_grove_22",
    },
    allowlist: new Set(),
    activityCounts: emptyActivity(),
    defaultUsernameResolver: () => Promise.resolve("fern_grove_22"),
    now: new Date("2026-07-09T00:00:00.000Z"),
  });

  assertEquals(row.classification, "likely_empty_ghost");
  assertEquals(row.cleanup_recommendation, "likely_empty_ghost_candidate_30d");
  assertEquals(row.age_bucket, "30_89d");
});

Deno.test("renderCsv escapes JSON activity source cells", () => {
  const csv = renderCsv([
    {
      user_id: "ghost-7",
      classification: "active_ghost",
      cleanup_recommendation: "keep_active_ghost",
      allowlisted: false,
      age_days: 1,
      age_bucket: "lt_7d",
      auth: {
        exists: true,
        created_at: "2026-07-08T00:00:00.000Z",
        last_sign_in_at: null,
        email: null,
        is_anonymous: true,
        providers: ["anonymous"],
      },
      public_user: {
        exists: true,
        created_at: "2026-07-08T00:00:00.000Z",
        email: null,
        subscription_tier: "free",
        subscription_expires_at: null,
        public_identity_source: "alias",
        public_author_name: "fern_grove_22",
        public_username: "fern_grove_22",
        custom_avatar_url: null,
      },
      identity_flags: defaultIdentityFlags(),
      activity: {
        total: 1,
        bySource: { scans: 1 },
      },
    },
  ]);

  assert(csv.includes('"{""scans"":1}"'));
});

Deno.test("requiredAdminApiKey prefers current Supabase secret key name", () => {
  assertEquals(
    requiredAdminApiKey({
      SUPABASE_SECRET_KEY: CURRENT_SECRET_KEY,
      SUPABASE_SERVICE_ROLE_KEY: LEGACY_SERVICE_ROLE_KEY,
    }),
    CURRENT_SECRET_KEY,
  );
});

Deno.test("requiredAdminApiKey prefers the explicit key and supports the platform dictionary", () => {
  assertEquals(
    requiredAdminApiKey({
      SUPABASE_SERVER_API_KEY: EXPLICIT_SECRET_KEY,
      SUPABASE_SECRET_KEYS: JSON.stringify({
        default: DEFAULT_SECRET_KEY,
      }),
      SUPABASE_SERVICE_ROLE_KEY: LEGACY_SERVICE_ROLE_KEY,
    }),
    EXPLICIT_SECRET_KEY,
  );
  assertEquals(
    requiredAdminApiKey({
      SUPABASE_SECRET_KEYS: JSON.stringify({
        worker: WORKER_SECRET_KEY,
        default: DEFAULT_SECRET_KEY,
      }),
    }),
    DEFAULT_SECRET_KEY,
  );
});

Deno.test("requiredAdminApiKey accepts legacy service role key name", () => {
  assertEquals(
    requiredAdminApiKey({
      SUPABASE_SERVICE_ROLE_KEY: LEGACY_SERVICE_ROLE_KEY,
    }),
    LEGACY_SERVICE_ROLE_KEY,
  );
});

Deno.test("requiredAdminApiKey rejects public or malformed privileged configuration", () => {
  const invalidEnvironments: Array<Record<string, string>> = [
    { SUPABASE_SERVER_API_KEY: "sb_publishable_public" },
    { SUPABASE_SERVICE_ROLE_KEY: "not-a-service-role-jwt" },
    { SUPABASE_SECRET_KEYS: '{"default":"sb_publishable_public"}' },
  ];
  for (
    const environment of invalidEnvironments
  ) {
    let rejected = false;
    try {
      requiredAdminApiKey(environment);
    } catch {
      rejected = true;
    }
    assert(rejected, "public or malformed server key must be rejected");
  }
});

Deno.test("requiredAdminApiKey tolerates copied shell assignments", () => {
  assertEquals(
    requiredAdminApiKey({
      SUPABASE_SECRET_KEY: `SUPABASE_SECRET_KEY="${CURRENT_SECRET_KEY}"`,
    }),
    CURRENT_SECRET_KEY,
  );
});

function emptyActivity(): ActivityCounts {
  return { total: 0, bySource: {} };
}

function defaultIdentityFlags(): PublicIdentityFlags {
  return {
    hasCustomDisplayName: false,
    hasCustomAuthorName: false,
    hasNonAliasIdentitySource: false,
    hasCustomAvatar: false,
    publicUsername: null,
    defaultPublicUsername: null,
    usernameCheckStatus: "missing",
    hasCustomPublicIdentity: false,
  };
}

function assert(condition: boolean, message = "assertion failed"): void {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T): void {
  if (actual !== expected) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
