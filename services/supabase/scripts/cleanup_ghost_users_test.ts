import {
  buildDryRunResult,
  cleanupEligibilityIssues,
  parseCleanupArgs,
  selectCleanupRows,
} from "./cleanup_ghost_users.ts";
import type {
  AuditSnapshotRow,
  GhostUserAuditReport,
} from "./audit_ghost_users.ts";

Deno.test("selectCleanupRows keeps only old empty anonymous ghosts and sorts oldest first", () => {
  const rows = [
    row({ user_id: "newer", age_days: 31 }),
    row({ user_id: "oldest", age_days: 120 }),
    row({
      user_id: "active",
      classification: "active_ghost",
      cleanup_recommendation: "keep_active_ghost",
      activity: { total: 1, bySource: { scans: 1 } },
    }),
  ];

  assertEquals(
    selectCleanupRows(rows, 30).map((candidate) => candidate.user_id).join(","),
    "oldest,newer",
  );
});

Deno.test("cleanupEligibilityIssues rejects real account signals", () => {
  const issues = cleanupEligibilityIssues(
    row({
      auth: {
        ...baseAuth(),
        email: "person@example.com",
        is_anonymous: false,
        providers: ["google"],
      },
    }),
    30,
  );

  assert(issues.includes("auth user is not anonymous"));
  assert(issues.includes("auth user has email"));
  assert(issues.includes("auth user has non-anonymous provider"));
});

Deno.test("cleanupEligibilityIssues rejects activity and custom identity", () => {
  const issues = cleanupEligibilityIssues(
    row({
      activity: { total: 2, bySource: { scans: 2 } },
      identity_flags: {
        ...baseIdentityFlags(),
        hasCustomPublicIdentity: true,
      },
    }),
    30,
  );

  assert(issues.includes("row has activity"));
  assert(issues.includes("row has custom public identity"));
});

Deno.test("cleanupEligibilityIssues explicitly rejects protected merge handoffs", () => {
  const issues = cleanupEligibilityIssues(
    row({
      activity: {
        total: 1,
        bySource: { ghost_profile_merge_handoff: 1 },
      },
    }),
    30,
  );

  assert(issues.includes("row has protected ghost merge handoff"));
});

Deno.test("buildDryRunResult applies limit without deleting", () => {
  const result = buildDryRunResult(
    report([
      row({ user_id: "a", age_days: 90 }),
      row({ user_id: "b", age_days: 80 }),
    ]),
    {
      ...parseCleanupArgs(["--snapshot-json", "/tmp/audit.json"]),
      limit: 1,
    },
    new Date("2026-07-09T18:00:00.000Z"),
  );

  assertEquals(result.mode, "dry_run");
  assertEquals(result.total_eligible, 2);
  assertEquals(result.selected_count, 1);
  assertEquals(result.deleted_auth_users.length, 0);
});

Deno.test("buildDryRunResult warns on stale snapshots", () => {
  const result = buildDryRunResult(
    report([row()], "2026-07-07T00:00:00.000Z"),
    parseCleanupArgs(["--snapshot-json", "/tmp/audit.json"]),
    new Date("2026-07-09T18:00:00.000Z"),
  );

  assertEquals(result.warnings.length, 1);
});

Deno.test("parseCleanupArgs captures execute confirmation flags", () => {
  const args = parseCleanupArgs([
    "--snapshot-json",
    "/tmp/audit.json",
    "--limit",
    "5",
    "--execute",
    "--confirm-delete-likely-empty-ghosts",
    "--output-json",
    "/tmp/cleanup.json",
  ]);

  assertEquals(args.snapshotJsonPath, "/tmp/audit.json");
  assertEquals(args.limit, 5);
  assertEquals(args.execute, true);
  assertEquals(args.confirmed, true);
  assertEquals(args.outputJsonPath, "/tmp/cleanup.json");
});

function report(
  rows: AuditSnapshotRow[],
  generatedAt = "2026-07-09T17:00:00.000Z",
): GhostUserAuditReport {
  return {
    summary: {
      generated_at: generatedAt,
      counts: {},
      missing_optional_sources: [],
      recommendations: {
        keep_real_account: 0,
        keep_active_ghost: 0,
        review_recent_empty_ghost: 0,
        likely_empty_ghost_candidate_30d: rows.length,
        review_public_profile_without_auth_user: 0,
      },
    },
    rows,
  };
}

function row(overrides: Partial<AuditSnapshotRow> = {}): AuditSnapshotRow {
  return {
    user_id: "ghost",
    classification: "likely_empty_ghost",
    cleanup_recommendation: "likely_empty_ghost_candidate_30d",
    allowlisted: false,
    age_days: 45,
    age_bucket: "30_89d",
    auth: baseAuth(),
    public_user: basePublicUser(),
    identity_flags: baseIdentityFlags(),
    activity: { total: 0, bySource: {} },
    ...overrides,
  };
}

function baseAuth(): AuditSnapshotRow["auth"] {
  return {
    exists: true,
    created_at: "2026-05-01T00:00:00.000Z",
    last_sign_in_at: "2026-05-01T00:00:00.000Z",
    email: null,
    is_anonymous: true,
    providers: ["anonymous"],
  };
}

function basePublicUser(): AuditSnapshotRow["public_user"] {
  return {
    exists: true,
    created_at: "2026-05-01T00:00:00.000Z",
    email: null,
    subscription_tier: "free",
    subscription_expires_at: null,
    public_identity_source: "alias",
    public_author_name: "fern_grove_22",
    public_username: "fern_grove_22",
    custom_avatar_url: null,
  };
}

function baseIdentityFlags(): AuditSnapshotRow["identity_flags"] {
  return {
    hasCustomDisplayName: false,
    hasCustomAuthorName: false,
    hasNonAliasIdentitySource: false,
    hasCustomAvatar: false,
    publicUsername: "fern_grove_22",
    defaultPublicUsername: "fern_grove_22",
    usernameCheckStatus: "matched_default",
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
