import {
  buildCleanupPlan,
  buildDryRunResult,
  cleanupCandidateSHA256,
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

Deno.test("cleanupEligibilityIssues rejects a recently used old Auth identity", () => {
  const issues = cleanupEligibilityIssues(
    row({
      auth: {
        ...baseAuth(),
        last_sign_in_at: "2026-08-08T00:00:00.000Z",
      },
    }),
    30,
    new Date("2026-08-09T00:00:00.000Z"),
  );

  assert(issues.includes("last sign-in is unknown or within 30 days"));
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

Deno.test("cleanupEligibilityIssues permits an otherwise-empty Auth-only shell", () => {
  const issues = cleanupEligibilityIssues(
    row({
      public_user: {
        ...basePublicUser(),
        exists: false,
        subscription_tier: null,
      },
    }),
    30,
  );

  assertEquals(issues.length, 0);
});

Deno.test("buildDryRunResult applies limit without deleting", async () => {
  const first = "00000000-0000-4000-8000-000000000101";
  const second = "00000000-0000-4000-8000-000000000102";
  const result = await buildDryRunResult(
    reportWithProtector([
      row({ user_id: first, age_days: 90 }),
      row({ user_id: second, age_days: 80 }),
    ]),
    {
      ...parseCleanupArgs(["--snapshot-json", "/tmp/audit.json"]),
      limit: 1,
    },
    new Date("2026-07-09T18:00:00.000Z"),
    revenueCatCsv([
      [first.toUpperCase(), "2026-04-01T00:00:00.000Z", "false", "0"],
      [second.toUpperCase(), "2026-04-01T00:00:00.000Z", "false", "0"],
    ]),
    protectedCohortCsv(),
  );

  assertEquals(result.mode, "dry_run");
  assertEquals(result.audit_eligible_count, 2);
  assertEquals(result.selected_count, 1);
  assertEquals(result.direct_auth_deletions, 0);
  assertEquals(result.direct_public_user_deletions, 0);
});

Deno.test("buildDryRunResult warns on stale snapshots", async () => {
  const candidate = "00000000-0000-4000-8000-000000000103";
  const result = await buildDryRunResult(
    reportWithProtector(
      [row({ user_id: candidate })],
      "2026-07-07T00:00:00.000Z",
    ),
    parseCleanupArgs(["--snapshot-json", "/tmp/audit.json"]),
    new Date("2026-07-09T18:00:00.000Z"),
    revenueCatCsv([]),
    protectedCohortCsv(),
  );

  assertEquals(result.warnings.length, 1);
});

Deno.test("buildDryRunResult fails closed when audit source coverage is missing", async () => {
  const candidate = "00000000-0000-4000-8000-000000000104";
  const incompleteReport = reportWithProtector([row({ user_id: candidate })]);
  delete (incompleteReport.summary as unknown as Record<string, unknown>)
    .missing_optional_sources;

  const result = await buildDryRunResult(
    incompleteReport,
    parseCleanupArgs(["--snapshot-json", "/tmp/audit.json"]),
    new Date("2026-07-09T18:00:00.000Z"),
    revenueCatCsv([]),
    protectedCohortCsv(),
  );

  assert(
    result.warnings.includes(
      "audit missing optional-source coverage inventory",
    ),
  );
});

Deno.test("cleanup plan excludes RevenueCat purchase, attribute, alias, and recent evidence", () => {
  const purchase = "00000000-0000-4000-8000-000000000111";
  const recent = "00000000-0000-4000-8000-000000000112";
  const alias = "00000000-0000-4000-8000-000000000113";
  const attributed = "00000000-0000-4000-8000-000000000114";
  const report = reportWithProtector([
    row({ user_id: purchase }),
    row({ user_id: recent }),
    row({ user_id: alias }),
    row({ user_id: attributed }),
  ]);
  const source = [
    "app_user_id;last_seen_at;is_rc_promo;total_spent;custom_attributes",
    `${purchase.toUpperCase()};2026-04-01T00:00:00.000Z;true;0;`,
    `${recent.toUpperCase()};2026-07-01T00:00:00.000Z;false;0;`,
    `legacy-alias;2026-04-01T00:00:00.000Z;false;0;"{""supabase_user_id"":{""value"":""${alias}""}}"`,
    `${attributed.toUpperCase()};2026-04-01T00:00:00.000Z;false;0;"{""$email"":{""value"":""protected@example.com""}}"`,
  ].join("\n");

  const plan = buildCleanupPlan({
    report,
    thresholdDays: 30,
    limit: 10,
    revenueCatSource: `${source}\n`,
    protectedCohortSource: protectedCohortCsv(),
    now: new Date("2026-07-09T18:00:00.000Z"),
  });

  assertEquals(plan.candidates.length, 0);
  assertEquals(plan.exclusions.length, 4);
});

Deno.test("candidate digest is deterministic across input order", async () => {
  const first = cleanupCandidate("00000000-0000-4000-8000-000000000121");
  const second = cleanupCandidate("00000000-0000-4000-8000-000000000122");
  assertEquals(
    await cleanupCandidateSHA256([first, second]),
    await cleanupCandidateSHA256([second, first]),
  );
});

Deno.test("parseCleanupArgs captures execute confirmation flags", () => {
  const args = parseCleanupArgs([
    "--snapshot-json",
    "/tmp/audit.json",
    "--revenuecat-customers-csv",
    "/tmp/revenuecat.csv",
    "--protected-cohort-csv",
    "/tmp/cohort.csv",
    "--limit",
    "5",
    "--execute",
    "--confirm-delete-likely-empty-ghosts",
    "--approved-plan-sha256",
    "a".repeat(64),
    "--confirm-count",
    "5",
    "--output-json",
    "/tmp/cleanup.json",
  ]);

  assertEquals(args.snapshotJsonPath, "/tmp/audit.json");
  assertEquals(args.limit, 5);
  assertEquals(args.execute, true);
  assertEquals(args.confirmed, true);
  assertEquals(args.approvedPlanSHA256, "a".repeat(64));
  assertEquals(args.confirmedCount, 5);
  assertEquals(args.outputJsonPath, "/tmp/cleanup.json");
});

const PROTECTED_USER_ID = "00000000-0000-4000-8000-000000000199";

function report(
  rows: AuditSnapshotRow[],
  generatedAt = "2026-07-09T17:00:00.000Z",
): GhostUserAuditReport {
  return {
    summary: {
      audit_contract_version: 2,
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

function reportWithProtector(
  rows: AuditSnapshotRow[],
  generatedAt = "2026-07-09T17:00:00.000Z",
): GhostUserAuditReport {
  return report([
    ...rows,
    row({
      user_id: PROTECTED_USER_ID,
      classification: "real_account",
      cleanup_recommendation: "keep_real_account",
      auth: { ...baseAuth(), is_anonymous: false, providers: ["email"] },
      public_user: { ...basePublicUser(), email: "tester@example.com" },
    }),
  ], generatedAt);
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

function revenueCatCsv(rows: string[][]): string {
  return [
    "app_user_id;last_seen_at;is_rc_promo;total_spent",
    ...rows.map((values) => values.join(";")),
  ].join("\n") + "\n";
}

function protectedCohortCsv(): string {
  return `id\n${PROTECTED_USER_ID}\n`;
}

function cleanupCandidate(userID: string) {
  return {
    user_id: userID,
    age_days: 45,
    auth_created_at: "2026-05-01T00:00:00.000Z",
    auth_last_sign_in_at: "2026-05-01T00:00:00.000Z",
    public_user_exists: true,
    revenuecat_customer_id: userID.toUpperCase(),
    revenuecat_export_state: "empty_inactive" as const,
    revenuecat_export_last_seen_at: "2026-05-01T00:00:00.000Z",
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
