/**
 * Dry-run-first issuance for account-owned beta, promotion, and support access.
 *
 * This tool never calls RevenueCat. It binds a reviewed, authenticated cohort
 * to a clean source SHA and a live database identity, then records every grant
 * and one immutable aggregate operation receipt in a single transaction.
 * Neither stdout nor the retained plan contains account identifiers.
 *
 * Required env:
 *   MERIAN_DATABASE_URL
 *
 * Additional apply-only env:
 *   MERIAN_ACCOUNT_ACCESS_GRANT_APPLY_CONFIRMATION=
 *     <target>:account-access-grant:<source-sha>:<operation-id>:<plan-sha256>
 */

import postgres, { type Sql } from "npm:postgres@3.4.7";
import { readPossiblyGzippedTextArtifact } from "./revenuecat_csv.ts";
import {
  selectBetaEntitlementCandidates,
  sha256Hex,
  validateGrantExpiration,
} from "./grant_revenuecat_beta_entitlements.ts";
import {
  canonicalJSONString,
  inspectDatabaseSystemIdentifier,
  sha256,
  validateTargetDatabaseURL,
  verifyCheckedOutSourceSha,
} from "./control_purchase_identity_rollout.ts";

export type AccountAccessGrantKind = "beta" | "promotion" | "support";

export interface AccountAccessGrantArgs {
  target: string;
  sourceSha: string;
  operationId: string;
  approvalSha256: string;
  usersCsvPath: string;
  cohortCsvPath: string;
  authAuditCsvPath: string;
  grantKind: AccountAccessGrantKind;
  expiresAt: string;
  maxUsers: number;
  summaryJsonPath: string;
  summaryMarkdownPath: string;
  apply: boolean;
  approvedPlanSha256: string | null;
  approvedPlanJsonPath: string | null;
}

export interface AccountAccessGrantDatabaseSnapshot {
  database_system_identifier: string;
  principal_mode: "legacy" | "stable";
  account_grant_mode: "dual_read" | "authoritative";
}

export interface AccountAccessGrantPlan {
  schema_version: 1;
  tool_version: 1;
  operation_id: string;
  target_environment: string;
  database_identity: {
    project_ref: string;
    system_identifier: string;
  };
  source_sha: string;
  approval_sha256: string;
  rollout: {
    principal_mode: "legacy" | "stable";
    account_grant_mode: "dual_read" | "authoritative";
  };
  grant: {
    kind: AccountAccessGrantKind;
    expires_at: string;
  };
  sources: {
    users_sha256: string;
    cohort_sha256: string;
    auth_audit_sha256: string;
    candidate_set_sha256: string;
  };
  cohort: {
    candidate_count: number;
    verified_anonymous_count: number;
    verified_linked_count: number;
    projection_counts: {
      free: number;
      timed_pro: number;
      permanent_pro: number;
    };
  };
}

export interface AccountAccessGrantSummary {
  mode: "dry_run" | "apply";
  plan_sha256: string;
  plan: AccountAccessGrantPlan;
  applied: boolean;
  already_applied: boolean;
  inserted_grant_count: number;
  existing_grant_count: number;
}

interface LoadedAccountAccessGrantInput {
  candidates: string[];
  usersSha256: string;
  cohortSha256: string;
  authAuditSha256: string;
  candidateSetSha256: string;
  verifiedAnonymousCount: number;
  verifiedLinkedCount: number;
  projectionCounts: {
    free: number;
    timed_pro: number;
    permanent_pro: number;
  };
}

interface AccountAccessGrantOperationRow {
  id: string;
  schema_version: number;
  target_environment: string;
  project_ref: string;
  database_system_identifier: string;
  source_sha: string;
  approval_sha256: string;
  plan_sha256: string;
  candidate_set_sha256: string;
  candidate_count: number;
  grant_kind: string;
  expires_at: string | Date;
  principal_mode: string;
  account_grant_mode: string;
}

interface ExistingGrantRow {
  account_user_id: string;
  grant_kind: string;
  expires_at: string | Date | null;
  revoked_at: string | Date | null;
}

const SHA_1 = /^[0-9a-f]{40}$/;
const SHA_256 = /^[0-9a-f]{64}$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const TARGET = /^[a-z][a-z0-9_-]{1,31}$/;
const DATABASE_SYSTEM_IDENTIFIER = /^[0-9]{1,20}$/;
const MAX_USERS = 500;

if (import.meta.main) {
  try {
    const args = parseAccountAccessGrantArgs(Deno.args);
    const databaseUrl = requiredEnv("MERIAN_DATABASE_URL");
    const summary = await executeAccountAccessGrant(
      args,
      databaseUrl,
      Deno.env.get("MERIAN_ACCOUNT_ACCESS_GRANT_APPLY_CONFIRMATION") ?? "",
    );
    console.log(JSON.stringify(summary, null, 2));
  } catch (error) {
    console.error(
      `Account access grant failed; code=${safeErrorCode(error)}`,
    );
    Deno.exit(1);
  }
}

export function parseAccountAccessGrantArgs(
  rawArgs: string[],
): AccountAccessGrantArgs {
  const values = new Map<string, string>();
  let apply = false;
  for (let index = 0; index < rawArgs.length; index += 1) {
    const token = rawArgs[index];
    if (token === "--apply") {
      if (apply) throw new AccountAccessGrantError("duplicate_apply_flag");
      apply = true;
      continue;
    }
    if (!token.startsWith("--")) {
      throw new AccountAccessGrantError("unexpected_argument");
    }
    const value = rawArgs[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new AccountAccessGrantError("missing_argument_value");
    }
    if (values.has(token)) {
      throw new AccountAccessGrantError("duplicate_argument");
    }
    values.set(token, value);
    index += 1;
  }

  const allowed = new Set([
    "--target",
    "--source-sha",
    "--operation-id",
    "--approval-sha256",
    "--users-csv",
    "--cohort-csv",
    "--auth-audit-csv",
    "--grant-kind",
    "--expires-at",
    "--max-users",
    "--summary-json",
    "--summary-markdown",
    "--approved-plan-sha256",
    "--approved-plan-json",
  ]);
  for (const key of values.keys()) {
    if (!allowed.has(key)) {
      throw new AccountAccessGrantError("unknown_argument");
    }
  }

  const target = requiredValue(values, "--target");
  const sourceSha = requiredValue(values, "--source-sha").toLowerCase();
  const operationId = requiredValue(values, "--operation-id").toLowerCase();
  const approvalSha256 = requiredValue(
    values,
    "--approval-sha256",
  ).toLowerCase();
  const grantKind = requiredValue(values, "--grant-kind");
  const maxUsersValue = values.get("--max-users") ?? String(MAX_USERS);
  const maxUsers = Number(maxUsersValue);
  const approvedPlanSha256 =
    values.get("--approved-plan-sha256")?.toLowerCase() ??
      null;
  const approvedPlanJsonPath = values.get("--approved-plan-json") ?? null;

  if (!TARGET.test(target)) {
    throw new AccountAccessGrantError("invalid_target");
  }
  if (!SHA_1.test(sourceSha)) {
    throw new AccountAccessGrantError("invalid_source_sha");
  }
  if (!UUID.test(operationId)) {
    throw new AccountAccessGrantError("invalid_operation_id");
  }
  if (!SHA_256.test(approvalSha256)) {
    throw new AccountAccessGrantError("invalid_approval_sha256");
  }
  if (!isGrantKind(grantKind)) {
    throw new AccountAccessGrantError("invalid_grant_kind");
  }
  if (!Number.isSafeInteger(maxUsers) || maxUsers < 1 || maxUsers > MAX_USERS) {
    throw new AccountAccessGrantError("invalid_max_users");
  }
  if (apply) {
    if (!approvedPlanSha256 || !SHA_256.test(approvedPlanSha256)) {
      throw new AccountAccessGrantError("missing_approved_plan_sha256");
    }
    if (!approvedPlanJsonPath) {
      throw new AccountAccessGrantError("missing_approved_plan_json");
    }
  } else if (approvedPlanSha256 || approvedPlanJsonPath) {
    throw new AccountAccessGrantError("approved_plan_requires_apply");
  }

  return {
    target,
    sourceSha,
    operationId,
    approvalSha256,
    usersCsvPath: requiredValue(values, "--users-csv"),
    cohortCsvPath: requiredValue(values, "--cohort-csv"),
    authAuditCsvPath: requiredValue(values, "--auth-audit-csv"),
    grantKind,
    expiresAt: requiredValue(values, "--expires-at"),
    maxUsers,
    summaryJsonPath: requiredValue(values, "--summary-json"),
    summaryMarkdownPath: requiredValue(values, "--summary-markdown"),
    apply,
    approvedPlanSha256,
    approvedPlanJsonPath,
  };
}

export async function executeAccountAccessGrant(
  args: AccountAccessGrantArgs,
  databaseUrl: string,
  applyConfirmation: string,
): Promise<AccountAccessGrantSummary> {
  await verifyCheckedOutSourceSha(args.sourceSha);
  const projectRef = validateTargetDatabaseURL(args.target, databaseUrl);
  const expiresAt = validateGrantExpiration(args.expiresAt, new Date());
  const input = await loadAccountAccessGrantInput(args);
  if (input.candidates.length > args.maxUsers) {
    throw new AccountAccessGrantError("candidate_count_exceeds_limit");
  }

  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    connect_timeout: 10,
    idle_timeout: 5,
    max_lifetime: 30,
  });
  try {
    if (!args.apply) {
      const snapshot = await sql.begin(async (transaction) => {
        await transaction.unsafe("SET TRANSACTION READ ONLY");
        await transaction.unsafe("SET LOCAL statement_timeout = '10s'");
        return await inspectAccountAccessGrantSnapshot(transaction);
      });
      const plan = buildAccountAccessGrantPlan(
        args,
        input,
        expiresAt,
        projectRef,
        snapshot,
      );
      const planSha256 = await sha256(canonicalJSONString(plan));
      const summary: AccountAccessGrantSummary = {
        mode: "dry_run",
        plan_sha256: planSha256,
        plan,
        applied: false,
        already_applied: false,
        inserted_grant_count: 0,
        existing_grant_count: 0,
      };
      await writeAccountAccessGrantSummary(summary, args);
      return summary;
    }

    const approved = parseApprovedAccountAccessGrantSummary(
      await Deno.readTextFile(args.approvedPlanJsonPath!),
    );
    const approvedSnapshot = snapshotFromApprovedPlan(approved.plan);
    const plan = buildAccountAccessGrantPlan(
      args,
      input,
      expiresAt,
      projectRef,
      approvedSnapshot,
    );
    const planSha256 = await sha256(canonicalJSONString(plan));
    await validateApprovedAccountAccessGrantSummary(
      approved,
      args,
      plan,
      planSha256,
    );
    const expectedConfirmation = [
      args.target,
      "account-access-grant",
      args.sourceSha,
      args.operationId,
      planSha256,
    ].join(":");
    if (applyConfirmation !== expectedConfirmation) {
      throw new AccountAccessGrantError("apply_confirmation_mismatch");
    }

    const sourceReferences = await Promise.all(
      input.candidates.map((accountUserId) =>
        accountAccessGrantSourceReference(args.operationId, accountUserId)
      ),
    );
    const result = await sql.begin(async (transaction) => {
      await transaction.unsafe(
        "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE",
      );
      await transaction.unsafe("SET LOCAL lock_timeout = '5s'");
      await transaction.unsafe("SET LOCAL statement_timeout = '30s'");
      await transaction`
        SELECT pg_catalog.PG_ADVISORY_XACT_LOCK(
          pg_catalog.HASHTEXTEXTENDED(
            'account-access-grant-operation:' || ${args.operationId},
            0::BIGINT
          )
        )
      `;
      const receiptRows = await transaction<AccountAccessGrantOperationRow[]>`
        SELECT
          operation.id::TEXT,
          operation.schema_version,
          operation.target_environment,
          operation.project_ref,
          operation.database_system_identifier,
          operation.source_sha,
          operation.approval_sha256,
          operation.plan_sha256,
          operation.candidate_set_sha256,
          operation.candidate_count,
          operation.grant_kind,
          operation.expires_at,
          operation.principal_mode,
          operation.account_grant_mode
        FROM internal.account_access_grant_operations AS operation
        WHERE operation.id = ${args.operationId}::UUID
        FOR UPDATE
      `;
      if (receiptRows.length > 1) {
        throw new AccountAccessGrantError("invalid_operation_receipt");
      }
      if (receiptRows.length === 1) {
        const liveSystemIdentifier = await inspectDatabaseSystemIdentifier(
          transaction,
        );
        if (
          liveSystemIdentifier !== plan.database_identity.system_identifier
        ) {
          throw new AccountAccessGrantError("database_target_mismatch");
        }
        assertOperationReceiptMatches(receiptRows[0], plan, planSha256);
        return {
          alreadyApplied: true,
          insertedGrantCount: 0,
          existingGrantCount: input.candidates.length,
        };
      }

      const liveSnapshot = await inspectAccountAccessGrantSnapshot(
        transaction,
        true,
      );
      const livePlan = buildAccountAccessGrantPlan(
        args,
        input,
        expiresAt,
        projectRef,
        liveSnapshot,
      );
      if (canonicalJSONString(livePlan) !== canonicalJSONString(plan)) {
        throw new AccountAccessGrantError("approved_plan_mismatch");
      }

      let insertedGrantCount = 0;
      let existingGrantCount = 0;
      for (let index = 0; index < input.candidates.length; index += 1) {
        const accountUserId = input.candidates[index];
        const sourceReference = sourceReferences[index];
        const existingRows = await transaction<ExistingGrantRow[]>`
          SELECT
            grant_row.account_user_id::TEXT,
            grant_row.grant_kind,
            grant_row.expires_at,
            grant_row.revoked_at
          FROM internal.account_access_grants AS grant_row
          WHERE grant_row.source_kind = 'operator'
            AND grant_row.source_reference_hash = ${sourceReference}
          FOR UPDATE
        `;
        if (existingRows.length > 1) {
          throw new AccountAccessGrantError("invalid_existing_grant");
        }
        if (existingRows.length === 1) {
          assertExistingGrantMatches(
            existingRows[0],
            accountUserId,
            args.grantKind,
            expiresAt,
          );
          existingGrantCount += 1;
          continue;
        }

        const grantRows = await transaction<Array<{ grant_id: string }>>`
          SELECT public.record_account_access_grant(
            ${accountUserId}::UUID,
            ${args.grantKind},
            ${expiresAt}::TIMESTAMPTZ,
            ${sourceReference}
          )::TEXT AS grant_id
        `;
        if (grantRows.length !== 1 || !UUID.test(grantRows[0].grant_id)) {
          throw new AccountAccessGrantError("invalid_grant_receipt");
        }
        insertedGrantCount += 1;
      }

      await transaction`
        INSERT INTO internal.account_access_grant_operations (
          id,
          schema_version,
          target_environment,
          project_ref,
          database_system_identifier,
          source_sha,
          approval_sha256,
          plan_sha256,
          candidate_set_sha256,
          candidate_count,
          grant_kind,
          expires_at,
          principal_mode,
          account_grant_mode
        ) VALUES (
          ${args.operationId}::UUID,
          1,
          ${args.target},
          ${projectRef},
          ${liveSnapshot.database_system_identifier},
          ${args.sourceSha},
          ${args.approvalSha256},
          ${planSha256},
          ${input.candidateSetSha256},
          ${input.candidates.length},
          ${args.grantKind},
          ${expiresAt}::TIMESTAMPTZ,
          ${liveSnapshot.principal_mode},
          ${liveSnapshot.account_grant_mode}
        )
      `;
      return {
        alreadyApplied: false,
        insertedGrantCount,
        existingGrantCount,
      };
    });

    const summary: AccountAccessGrantSummary = {
      mode: "apply",
      plan_sha256: planSha256,
      plan,
      applied: true,
      already_applied: result.alreadyApplied,
      inserted_grant_count: result.insertedGrantCount,
      existing_grant_count: result.existingGrantCount,
    };
    await writeAccountAccessGrantSummary(summary, args);
    return summary;
  } finally {
    await sql.end({ timeout: 5 });
  }
}

export async function loadAccountAccessGrantInput(
  args: Pick<
    AccountAccessGrantArgs,
    "usersCsvPath" | "cohortCsvPath" | "authAuditCsvPath"
  >,
): Promise<LoadedAccountAccessGrantInput> {
  const [users, cohort, authAudit] = await Promise.all([
    readPossiblyGzippedTextArtifact(args.usersCsvPath),
    readPossiblyGzippedTextArtifact(args.cohortCsvPath),
    readPossiblyGzippedTextArtifact(args.authAuditCsvPath),
  ]);
  const selection = selectBetaEntitlementCandidates({
    usersSource: users.text,
    cohortSource: cohort.text,
    authAuditSource: authAudit.text,
  });
  const candidates = selection.candidates.map((candidate) =>
    candidate.app_user_id.toLowerCase()
  );
  return {
    candidates,
    usersSha256: await sha256Hex(users.sourceBytes),
    cohortSha256: await sha256Hex(cohort.sourceBytes),
    authAuditSha256: await sha256Hex(authAudit.sourceBytes),
    candidateSetSha256: await sha256(canonicalJSONString(candidates)),
    verifiedAnonymousCount: selection.verifiedGhostCount,
    verifiedLinkedCount: selection.verifiedLinkedCount,
    projectionCounts: selection.projectionCounts,
  };
}

export function buildAccountAccessGrantPlan(
  args: Pick<
    AccountAccessGrantArgs,
    | "target"
    | "sourceSha"
    | "operationId"
    | "approvalSha256"
    | "grantKind"
  >,
  input: LoadedAccountAccessGrantInput,
  expiresAt: string,
  projectRef: string,
  snapshot: AccountAccessGrantDatabaseSnapshot,
): AccountAccessGrantPlan {
  return {
    schema_version: 1,
    tool_version: 1,
    operation_id: args.operationId,
    target_environment: args.target,
    database_identity: {
      project_ref: projectRef,
      system_identifier: snapshot.database_system_identifier,
    },
    source_sha: args.sourceSha,
    approval_sha256: args.approvalSha256,
    rollout: {
      principal_mode: snapshot.principal_mode,
      account_grant_mode: snapshot.account_grant_mode,
    },
    grant: {
      kind: args.grantKind,
      expires_at: expiresAt,
    },
    sources: {
      users_sha256: input.usersSha256,
      cohort_sha256: input.cohortSha256,
      auth_audit_sha256: input.authAuditSha256,
      candidate_set_sha256: input.candidateSetSha256,
    },
    cohort: {
      candidate_count: input.candidates.length,
      verified_anonymous_count: input.verifiedAnonymousCount,
      verified_linked_count: input.verifiedLinkedCount,
      projection_counts: input.projectionCounts,
    },
  };
}

function snapshotFromApprovedPlan(
  plan: AccountAccessGrantPlan,
): AccountAccessGrantDatabaseSnapshot {
  if (
    !isObject(plan) || !isObject(plan.database_identity) ||
    !isObject(plan.rollout) ||
    !DATABASE_SYSTEM_IDENTIFIER.test(
      String(plan.database_identity.system_identifier ?? ""),
    ) ||
    (plan.rollout.principal_mode !== "legacy" &&
      plan.rollout.principal_mode !== "stable") ||
    (plan.rollout.account_grant_mode !== "dual_read" &&
      plan.rollout.account_grant_mode !== "authoritative")
  ) {
    throw new AccountAccessGrantError("invalid_approved_plan_shape");
  }
  return {
    database_system_identifier: plan.database_identity.system_identifier,
    principal_mode: plan.rollout.principal_mode,
    account_grant_mode: plan.rollout.account_grant_mode,
  };
}

export async function inspectAccountAccessGrantSnapshot(
  sql: Sql,
  lockConfig = false,
): Promise<AccountAccessGrantDatabaseSnapshot> {
  const systemIdentifier = await inspectDatabaseSystemIdentifier(sql);
  const lockClause = lockConfig ? " FOR UPDATE" : "";
  const rows = await sql.unsafe<
    Array<{
      principal_mode: "legacy" | "stable";
      account_grant_mode: "dual_read" | "authoritative";
    }>
  >(`
    SELECT config.principal_mode, config.account_grant_mode
    FROM internal.purchase_identity_rollout_config AS config
    WHERE config.config_key = 'current'${lockClause}
  `);
  if (rows.length !== 1) {
    throw new AccountAccessGrantError("rollout_config_unavailable");
  }
  return {
    database_system_identifier: systemIdentifier,
    ...rows[0],
  };
}

export async function accountAccessGrantSourceReference(
  operationId: string,
  accountUserId: string,
): Promise<string> {
  return await sha256(
    `merian-account-access-grant-v1\n${operationId.toLowerCase()}\n${accountUserId.toLowerCase()}\n`,
  );
}

export function assertOperationReceiptMatches(
  receipt: AccountAccessGrantOperationRow,
  plan: AccountAccessGrantPlan,
  planSha256: string,
): void {
  if (
    receipt.id.toLowerCase() !== plan.operation_id ||
    Number(receipt.schema_version) !== plan.schema_version ||
    receipt.target_environment !== plan.target_environment ||
    receipt.project_ref !== plan.database_identity.project_ref ||
    receipt.database_system_identifier !==
      plan.database_identity.system_identifier ||
    receipt.source_sha !== plan.source_sha ||
    receipt.approval_sha256 !== plan.approval_sha256 ||
    receipt.plan_sha256 !== planSha256 ||
    receipt.candidate_set_sha256 !== plan.sources.candidate_set_sha256 ||
    Number(receipt.candidate_count) !== plan.cohort.candidate_count ||
    receipt.grant_kind !== plan.grant.kind ||
    canonicalTimestamp(receipt.expires_at) !== plan.grant.expires_at ||
    receipt.principal_mode !== plan.rollout.principal_mode ||
    receipt.account_grant_mode !== plan.rollout.account_grant_mode
  ) {
    throw new AccountAccessGrantError("operation_receipt_conflict");
  }
}

export function assertExistingGrantMatches(
  grant: ExistingGrantRow,
  accountUserId: string,
  grantKind: AccountAccessGrantKind,
  expiresAt: string,
): void {
  if (
    grant.account_user_id.toLowerCase() !== accountUserId.toLowerCase() ||
    grant.grant_kind !== grantKind ||
    canonicalTimestamp(grant.expires_at) !== expiresAt ||
    grant.revoked_at !== null
  ) {
    throw new AccountAccessGrantError("existing_grant_conflict");
  }
}

export function parseApprovedAccountAccessGrantSummary(
  text: string,
): AccountAccessGrantSummary {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new AccountAccessGrantError("invalid_approved_plan_json");
  }
  if (!isObject(value) || !isObject(value.plan)) {
    throw new AccountAccessGrantError("invalid_approved_plan_shape");
  }
  assertExactKeys(value, [
    "mode",
    "plan_sha256",
    "plan",
    "applied",
    "already_applied",
    "inserted_grant_count",
    "existing_grant_count",
  ]);
  return value as unknown as AccountAccessGrantSummary;
}

export async function validateApprovedAccountAccessGrantSummary(
  summary: AccountAccessGrantSummary,
  args: Pick<
    AccountAccessGrantArgs,
    "approvedPlanSha256" | "operationId" | "sourceSha" | "target"
  >,
  currentPlan: AccountAccessGrantPlan,
  currentPlanSha256: string,
): Promise<void> {
  if (
    summary.mode !== "dry_run" || summary.applied !== false ||
    summary.already_applied !== false ||
    summary.inserted_grant_count !== 0 ||
    summary.existing_grant_count !== 0 ||
    summary.plan_sha256 !== args.approvedPlanSha256 ||
    summary.plan_sha256 !== currentPlanSha256 ||
    summary.plan.operation_id !== args.operationId ||
    summary.plan.source_sha !== args.sourceSha ||
    summary.plan.target_environment !== args.target ||
    await sha256(canonicalJSONString(summary.plan)) !== summary.plan_sha256 ||
    canonicalJSONString(summary.plan) !== canonicalJSONString(currentPlan)
  ) {
    throw new AccountAccessGrantError("approved_plan_mismatch");
  }
}

async function writeAccountAccessGrantSummary(
  summary: AccountAccessGrantSummary,
  args: Pick<
    AccountAccessGrantArgs,
    "summaryJsonPath" | "summaryMarkdownPath"
  >,
): Promise<void> {
  await Deno.writeTextFile(
    args.summaryJsonPath,
    `${JSON.stringify(summary, null, 2)}\n`,
  );
  const lines = [
    "# Account access grant operation",
    "",
    `- Mode: \`${summary.mode}\``,
    `- Plan SHA-256: \`${summary.plan_sha256}\``,
    `- Source SHA: \`${summary.plan.source_sha}\``,
    `- Target: \`${summary.plan.target_environment}\``,
    `- Grant kind: \`${summary.plan.grant.kind}\``,
    `- Expires at: \`${summary.plan.grant.expires_at}\``,
    `- Candidate count: \`${summary.plan.cohort.candidate_count}\``,
    `- Inserted grants: \`${summary.inserted_grant_count}\``,
    `- Existing grants: \`${summary.existing_grant_count}\``,
    `- Applied: \`${summary.applied}\``,
    `- Already applied: \`${summary.already_applied}\``,
    "",
    "The retained summary contains aggregate counts and digests only. Cohort identities remain outside source control and in the private database ledger.",
    "",
  ];
  await Deno.writeTextFile(args.summaryMarkdownPath, lines.join("\n"));
}

function canonicalTimestamp(value: string | Date | null): string | null {
  if (value === null) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(parsed.getTime())) {
    throw new AccountAccessGrantError("invalid_receipt_timestamp");
  }
  return parsed.toISOString();
}

function isGrantKind(value: string): value is AccountAccessGrantKind {
  return value === "beta" || value === "promotion" || value === "support";
}

function requiredValue(values: Map<string, string>, key: string): string {
  const value = values.get(key);
  if (!value) throw new AccountAccessGrantError("missing_required_argument");
  return value;
}

function requiredEnv(key: string): string {
  const value = Deno.env.get(key)?.trim() ?? "";
  if (!value) throw new AccountAccessGrantError("missing_database_url");
  return value;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function assertExactKeys(
  value: Record<string, unknown>,
  expected: string[],
): void {
  const actual = Object.keys(value).sort();
  const required = [...expected].sort();
  if (canonicalJSONString(actual) !== canonicalJSONString(required)) {
    throw new AccountAccessGrantError("invalid_approved_plan_shape");
  }
}

function safeErrorCode(error: unknown): string {
  if (error instanceof AccountAccessGrantError) return error.code;
  if (error instanceof Error && /^[a-z][a-z0-9_]{0,63}$/.test(error.message)) {
    return error.message;
  }
  const candidate = error instanceof Error ? error.name : typeof error;
  return /^[A-Za-z][A-Za-z0-9]{0,63}$/.test(candidate)
    ? candidate
    : "OperationError";
}

class AccountAccessGrantError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "AccountAccessGrantError";
    this.code = /^[a-z][a-z0-9_]{0,63}$/.test(code)
      ? code
      : "account_access_grant_failed";
  }
}
