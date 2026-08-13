import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "@std/assert";
import {
  type AccountAccessGrantPlan,
  accountAccessGrantSourceReference,
  type AccountAccessGrantSummary,
  assertExistingGrantMatches,
  assertOperationReceiptMatches,
  buildAccountAccessGrantPlan,
  parseAccountAccessGrantArgs,
  validateApprovedAccountAccessGrantSummary,
} from "./grant_account_access_entitlements.ts";
import {
  canonicalJSONString,
  sha256,
} from "./control_purchase_identity_rollout.ts";

const SOURCE_SHA = "a".repeat(40);
const APPROVAL_SHA = "b".repeat(64);
const OPERATION_ID = "123e4567-e89b-42d3-a456-426614174000";
const USER_ONE = "123e4567-e89b-42d3-a456-426614174001";
const USER_TWO = "123e4567-e89b-42d3-a456-426614174002";
const SYSTEM_IDENTIFIER = "1234567890123456789";

Deno.test("account grant arguments require a dry-run/apply approval boundary", () => {
  const base = requiredArgs();
  const parsed = parseAccountAccessGrantArgs(base);
  assertEquals(parsed.apply, false);
  assertEquals(parsed.grantKind, "beta");
  assertEquals(parsed.maxUsers, 500);

  assertThrows(() => parseAccountAccessGrantArgs([...base, "--unknown", "x"]));
  assertThrows(() =>
    parseAccountAccessGrantArgs([
      ...base,
      "--approved-plan-sha256",
      "c".repeat(64),
    ])
  );
  assertThrows(() => parseAccountAccessGrantArgs([...base, "--apply"]));

  const apply = parseAccountAccessGrantArgs([
    ...base,
    "--apply",
    "--approved-plan-sha256",
    "c".repeat(64),
    "--approved-plan-json",
    "/secure/approved.json",
  ]);
  assertEquals(apply.apply, true);
  assertEquals(apply.approvedPlanSha256, "c".repeat(64));
});

Deno.test("account grant plan retains only aggregate cohort evidence", () => {
  const plan = fixturePlan();
  const serialized = canonicalJSONString(plan);
  assertEquals(plan.cohort.candidate_count, 2);
  assertEquals(plan.cohort.verified_anonymous_count, 1);
  assertStringIncludes(serialized, "candidate_set_sha256");
  assertEquals(serialized.includes(USER_ONE), false);
  assertEquals(serialized.includes(USER_TWO), false);
  assertEquals(serialized.includes("app_user_id"), false);
});

Deno.test("account grant source references are stable and account-specific", async () => {
  const first = await accountAccessGrantSourceReference(OPERATION_ID, USER_ONE);
  const replay = await accountAccessGrantSourceReference(
    OPERATION_ID.toUpperCase(),
    USER_ONE.toUpperCase(),
  );
  const second = await accountAccessGrantSourceReference(
    OPERATION_ID,
    USER_TWO,
  );
  assertEquals(first, replay);
  assertEquals(first.length, 64);
  assertEquals(first === second, false);
});

Deno.test("approved account grant plan rejects any cohort or database drift", async () => {
  const plan = fixturePlan();
  const planSha = await sha256(canonicalJSONString(plan));
  const summary = fixtureSummary(plan, planSha);
  await validateApprovedAccountAccessGrantSummary(
    summary,
    {
      approvedPlanSha256: planSha,
      operationId: OPERATION_ID,
      sourceSha: SOURCE_SHA,
      target: "production",
    },
    plan,
    planSha,
  );

  await assertRejects(() =>
    validateApprovedAccountAccessGrantSummary(
      summary,
      {
        approvedPlanSha256: planSha,
        operationId: OPERATION_ID,
        sourceSha: SOURCE_SHA,
        target: "production",
      },
      {
        ...plan,
        rollout: { ...plan.rollout, account_grant_mode: "authoritative" },
      },
      planSha,
    )
  );
});

Deno.test("account grant receipt replay is exact and immutable", async () => {
  const plan = fixturePlan();
  const planSha = await sha256(canonicalJSONString(plan));
  const receipt = {
    id: OPERATION_ID,
    schema_version: 1,
    target_environment: "production",
    project_ref: "qlarqavoqhkuwzmevrmf",
    database_system_identifier: SYSTEM_IDENTIFIER,
    source_sha: SOURCE_SHA,
    approval_sha256: APPROVAL_SHA,
    plan_sha256: planSha,
    candidate_set_sha256: plan.sources.candidate_set_sha256,
    candidate_count: 2,
    grant_kind: "beta",
    expires_at: "2026-12-01T00:00:00.000Z",
    principal_mode: "stable",
    account_grant_mode: "dual_read",
  };
  assertOperationReceiptMatches(receipt, plan, planSha);
  assertThrows(() =>
    assertOperationReceiptMatches(
      { ...receipt, candidate_count: 3 },
      plan,
      planSha,
    )
  );
});

Deno.test("existing grant replay never revives or retargets a grant", () => {
  const grant = {
    account_user_id: USER_ONE,
    grant_kind: "beta",
    expires_at: "2026-12-01T00:00:00.000Z",
    revoked_at: null,
  };
  assertExistingGrantMatches(
    grant,
    USER_ONE,
    "beta",
    "2026-12-01T00:00:00.000Z",
  );
  assertThrows(() =>
    assertExistingGrantMatches(
      { ...grant, account_user_id: USER_TWO },
      USER_ONE,
      "beta",
      "2026-12-01T00:00:00.000Z",
    )
  );
  assertThrows(() =>
    assertExistingGrantMatches(
      { ...grant, revoked_at: "2026-11-01T00:00:00.000Z" },
      USER_ONE,
      "beta",
      "2026-12-01T00:00:00.000Z",
    )
  );
});

function requiredArgs(): string[] {
  return [
    "--target",
    "production",
    "--source-sha",
    SOURCE_SHA,
    "--operation-id",
    OPERATION_ID,
    "--approval-sha256",
    APPROVAL_SHA,
    "--users-csv",
    "/secure/users.csv",
    "--cohort-csv",
    "/secure/cohort.csv",
    "--auth-audit-csv",
    "/secure/auth.csv",
    "--grant-kind",
    "beta",
    "--expires-at",
    "2026-12-01T00:00:00Z",
    "--summary-json",
    "/tmp/summary.json",
    "--summary-markdown",
    "/tmp/summary.md",
  ];
}

function fixturePlan(): AccountAccessGrantPlan {
  return buildAccountAccessGrantPlan(
    {
      target: "production",
      sourceSha: SOURCE_SHA,
      operationId: OPERATION_ID,
      approvalSha256: APPROVAL_SHA,
      grantKind: "beta",
    },
    {
      candidates: [USER_ONE, USER_TWO],
      usersSha256: "c".repeat(64),
      cohortSha256: "d".repeat(64),
      authAuditSha256: "e".repeat(64),
      candidateSetSha256: "f".repeat(64),
      verifiedAnonymousCount: 1,
      verifiedLinkedCount: 1,
      projectionCounts: { free: 2, timed_pro: 0, permanent_pro: 0 },
    },
    "2026-12-01T00:00:00.000Z",
    "qlarqavoqhkuwzmevrmf",
    {
      database_system_identifier: SYSTEM_IDENTIFIER,
      principal_mode: "stable",
      account_grant_mode: "dual_read",
    },
  );
}

function fixtureSummary(
  plan: AccountAccessGrantPlan,
  planSha: string,
): AccountAccessGrantSummary {
  return {
    mode: "dry_run",
    plan_sha256: planSha,
    plan,
    applied: false,
    already_applied: false,
    inserted_grant_count: 0,
    existing_grant_count: 0,
  };
}
