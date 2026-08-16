/**
 * Dry-run-first, database-owner-only control for purchase identity rollout.
 *
 * This script never changes RevenueCat, deploys code, or distributes iOS. It
 * changes one database rollout axis only when --apply is paired with the exact
 * approved dry-run digest and an explicit environment confirmation.
 *
 * Required env:
 *   MERIAN_DATABASE_URL
 *
 * Additional apply-only env:
 *   MERIAN_PURCHASE_IDENTITY_ROLLOUT_APPLY_CONFIRMATION=
 *     <target>:<action>:<source-sha>:<approved-plan-sha256>
 */

import postgres, { type Sql } from "npm:postgres@3.4.7";

export type PurchaseIdentityRolloutAction =
  | "enable_stable"
  | "rollback_stable"
  | "enable_authoritative"
  | "rollback_authoritative";

type EvidenceStatus = "passed" | "pending";

export interface PurchaseIdentityRolloutArgs {
  action: PurchaseIdentityRolloutAction;
  target: string;
  sourceSha: string;
  minimumClientProtocol: number;
  evidenceJsonPath: string;
  operationId: string;
  approvalSha256: string;
  rollbackOf: string | null;
  summaryJsonPath: string;
  summaryMarkdownPath: string;
  apply: boolean;
  approvedPlanSha256: string | null;
  approvedPlanJsonPath: string | null;
}

export interface PurchaseIdentityRolloutEvidence {
  schema_version: 2;
  source_sha: string;
  reviewed_at: string;
  artifacts: {
    candidate_validation_url: string;
    backend_deploy_url: string;
    ios_test_url: string;
    physical_device_matrix_url: string;
    revenuecat_matrix_url: string;
    health_monitor_url: string;
  };
  candidate: {
    validation: EvidenceStatus;
    exact_sha_deploy_smoke: EvidenceStatus;
  };
  database: {
    disposable_replay: EvidenceStatus;
    pgtap: EvidenceStatus;
    concurrency: EvidenceStatus;
    signout_rotation_concurrency: EvidenceStatus;
    lint: EvidenceStatus;
    security_advisor: EvidenceStatus;
  };
  ios: {
    unit_tests: EvidenceStatus;
    ui_tests: EvidenceStatus;
    clean_device_apple: EvidenceStatus;
    clean_device_google: EvidenceStatus;
    kill_relaunch: EvidenceStatus;
    keychain_unavailable: EvidenceStatus;
    offline_retry: EvidenceStatus;
    account_switch: EvidenceStatus;
    account_deletion: EvidenceStatus;
    signout_rotation_recovery: EvidenceStatus;
    signout_rotation_unrelated_session_rejection: EvidenceStatus;
    signout_rotation_entitlement_gate: EvidenceStatus;
  };
  revenuecat: {
    restore_behavior: "transfer_to_new_app_user_id" | "unverified";
    active_subscription: EvidenceStatus;
    renewal: EvidenceStatus;
    refund: EvidenceStatus;
    expiration: EvidenceStatus;
    lifetime: EvidenceStatus;
    seven_day_pass: EvidenceStatus;
    promotional_only: EvidenceStatus;
    mixed_storekit_promotion: EvidenceStatus;
    timeout_reconciliation: EvidenceStatus;
    duplicate_delivery: EvidenceStatus;
    attribute_scrub: EvidenceStatus;
    anonymous_app_user_id_count: number;
    auth_rotation_receipt_sync_count: number;
    auth_rotation_customer_transfer_count: number;
  };
  compatibility: {
    old_client_new_backend: EvidenceStatus;
    legacy_handoff_retained: EvidenceStatus;
    stable_rollback_rehearsal: EvidenceStatus;
    live_rotation_rollback_support: EvidenceStatus;
  };
  monitoring: {
    required_principal_health: EvidenceStatus;
    required_signout_rotation_health: EvidenceStatus;
    signout_rotation_expiry_and_thresholds: EvidenceStatus;
    queue_and_lease_health: EvidenceStatus;
  };
  account_grants: {
    projection_divergence_count: number;
    issuance_cutover: EvidenceStatus;
    authoritative_rollback_rehearsal: EvidenceStatus;
  };
  approval: {
    reference_sha256: string;
  };
}

export interface PurchaseIdentityRolloutDatabaseSnapshot {
  database_system_identifier: string;
  principal_mode: "legacy" | "stable";
  account_grant_mode: "dual_read" | "authoritative";
  minimum_client_protocol: number;
  active_principal_count: number;
  pending_principal_count: number;
  stale_pending_principal_count: number;
  unbound_active_principal_count: number;
  legacy_due_count: number;
  legacy_expired_claim_count: number;
  principal_due_count: number;
  principal_expired_claim_count: number;
}

export interface PurchaseIdentityRolloutPlan {
  schema_version: 1;
  tool_version: 1;
  operation_id: string;
  action: PurchaseIdentityRolloutAction;
  target_environment: string;
  database_identity: {
    project_ref: string;
    system_identifier: string;
  };
  source_sha: string;
  evidence_sha256: string;
  approval_sha256: string;
  rollback_of: string | null;
  before: {
    principal_mode: "legacy" | "stable";
    account_grant_mode: "dual_read" | "authoritative";
    minimum_client_protocol: number;
  };
  after: {
    principal_mode: "legacy" | "stable";
    account_grant_mode: "dual_read" | "authoritative";
    minimum_client_protocol: number;
  };
  health: Omit<
    PurchaseIdentityRolloutDatabaseSnapshot,
    | "database_system_identifier"
    | "principal_mode"
    | "account_grant_mode"
    | "minimum_client_protocol"
  >;
}

export interface PurchaseIdentityRolloutSummary {
  mode: "dry_run" | "apply";
  plan_sha256: string;
  plan: PurchaseIdentityRolloutPlan;
  applied: boolean;
  already_applied: boolean;
}

interface AppliedOperationRow {
  operation_id: string;
  applied_action: string;
  principal_mode: string;
  account_grant_mode: string;
  minimum_client_protocol: number;
  already_applied: boolean;
}

const SHA_1 = /^[0-9a-f]{40}$/;
const SHA_256 = /^[0-9a-f]{64}$/;
const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const TARGET = /^[a-z][a-z0-9_-]{1,31}$/;
const DATABASE_SYSTEM_IDENTIFIER = /^[0-9]{1,20}$/;
const TARGET_PROJECT_REFS: Readonly<Record<string, string>> = {
  production: "qlarqavoqhkuwzmevrmf",
};
const MAX_EVIDENCE_AGE_MS = 24 * 60 * 60 * 1_000;
const MAX_EVIDENCE_FUTURE_SKEW_MS = 5 * 60 * 1_000;

if (import.meta.main) {
  try {
    const args = parsePurchaseIdentityRolloutArgs(Deno.args);
    const databaseUrl = requiredEnv("MERIAN_DATABASE_URL");
    const summary = await executePurchaseIdentityRollout(
      args,
      databaseUrl,
      Deno.env.get(
        "MERIAN_PURCHASE_IDENTITY_ROLLOUT_APPLY_CONFIRMATION",
      ) ?? "",
    );
    console.log(JSON.stringify(summary, null, 2));
  } catch (error) {
    console.error(
      `Purchase identity rollout control failed; code=${safeErrorCode(error)}`,
    );
    Deno.exit(1);
  }
}

export function parsePurchaseIdentityRolloutArgs(
  rawArgs: string[],
): PurchaseIdentityRolloutArgs {
  const values = new Map<string, string>();
  let apply = false;
  for (let index = 0; index < rawArgs.length; index += 1) {
    const token = rawArgs[index];
    if (token === "--apply") {
      if (apply) throw new RolloutControlError("duplicate_apply_flag");
      apply = true;
      continue;
    }
    if (!token.startsWith("--")) {
      throw new RolloutControlError("unexpected_argument");
    }
    const value = rawArgs[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new RolloutControlError("missing_argument_value");
    }
    if (values.has(token)) {
      throw new RolloutControlError("duplicate_argument");
    }
    values.set(token, value);
    index += 1;
  }

  const allowed = new Set([
    "--action",
    "--target",
    "--source-sha",
    "--minimum-client-protocol",
    "--evidence-json",
    "--operation-id",
    "--approval-sha256",
    "--rollback-of",
    "--summary-json",
    "--summary-markdown",
    "--approved-plan-sha256",
    "--approved-plan-json",
  ]);
  for (const key of values.keys()) {
    if (!allowed.has(key)) {
      throw new RolloutControlError("unknown_argument");
    }
  }

  const action = requiredValue(values, "--action");
  if (!isRolloutAction(action)) {
    throw new RolloutControlError("invalid_action");
  }
  const target = requiredValue(values, "--target");
  const sourceSha = requiredValue(values, "--source-sha").toLowerCase();
  const operationId = requiredValue(values, "--operation-id").toLowerCase();
  const approvalSha256 = requiredValue(
    values,
    "--approval-sha256",
  ).toLowerCase();
  const minimumClientProtocol = Number(
    requiredValue(values, "--minimum-client-protocol"),
  );
  const approvedPlanSha256 = values.get("--approved-plan-sha256")
    ?.toLowerCase() ?? null;
  const approvedPlanJsonPath = values.get("--approved-plan-json") ?? null;
  const rollbackOf = values.get("--rollback-of")?.toLowerCase() ?? null;

  if (!TARGET.test(target)) throw new RolloutControlError("invalid_target");
  projectRefForTarget(target);
  if (!SHA_1.test(sourceSha)) {
    throw new RolloutControlError("invalid_source_sha");
  }
  if (!UUID.test(operationId)) {
    throw new RolloutControlError("invalid_operation_id");
  }
  if (!SHA_256.test(approvalSha256)) {
    throw new RolloutControlError("invalid_approval_sha256");
  }
  if (
    !Number.isInteger(minimumClientProtocol) ||
    minimumClientProtocol < 1 || minimumClientProtocol > 1000
  ) {
    throw new RolloutControlError("invalid_minimum_client_protocol");
  }
  const isRollback = action.startsWith("rollback_");
  if (isRollback !== (rollbackOf !== null)) {
    throw new RolloutControlError("invalid_rollback_reference");
  }
  if (rollbackOf !== null && !UUID.test(rollbackOf)) {
    throw new RolloutControlError("invalid_rollback_reference");
  }
  if (
    apply && (
      approvedPlanSha256 === null || !SHA_256.test(approvedPlanSha256) ||
      approvedPlanJsonPath === null
    )
  ) {
    throw new RolloutControlError("approved_plan_required");
  }
  if (
    !apply && (approvedPlanSha256 !== null || approvedPlanJsonPath !== null)
  ) {
    throw new RolloutControlError("approved_plan_apply_only");
  }

  return {
    action,
    target,
    sourceSha,
    minimumClientProtocol,
    evidenceJsonPath: requiredValue(values, "--evidence-json"),
    operationId,
    approvalSha256,
    rollbackOf,
    summaryJsonPath: requiredValue(values, "--summary-json"),
    summaryMarkdownPath: requiredValue(values, "--summary-markdown"),
    apply,
    approvedPlanSha256,
    approvedPlanJsonPath,
  };
}

export async function executePurchaseIdentityRollout(
  args: PurchaseIdentityRolloutArgs,
  databaseUrl: string,
  applyConfirmation: string,
): Promise<PurchaseIdentityRolloutSummary> {
  await verifyCheckedOutSourceSha(args.sourceSha);
  const targetProjectRef = validateTargetDatabaseURL(
    args.target,
    databaseUrl,
  );
  const evidenceText = await Deno.readTextFile(args.evidenceJsonPath);
  const evidence = parsePurchaseIdentityRolloutEvidence(evidenceText);
  const evidenceSha256 = await sha256(canonicalJSONString(evidence));
  validatePurchaseIdentityRolloutEvidence(evidence, args);

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
        return await inspectPurchaseIdentityRolloutSnapshot(transaction);
      });
      const plan = buildPurchaseIdentityRolloutPlan(
        args,
        evidenceSha256,
        snapshot,
        targetProjectRef,
      );
      const planSha256 = await sha256(canonicalJSONString(plan));
      const summary: PurchaseIdentityRolloutSummary = {
        mode: "dry_run",
        plan_sha256: planSha256,
        plan,
        applied: false,
        already_applied: false,
      };
      await writePurchaseIdentityRolloutSummary(summary, args);
      return summary;
    }

    const approvedPlan = args.approvedPlanSha256!;
    const approvedPlanSummary = parseApprovedPlanSummary(
      await Deno.readTextFile(args.approvedPlanJsonPath!),
    );
    const approvedPlanObject = await validateApprovedPlanSummary(
      approvedPlanSummary,
      args,
      evidenceSha256,
      targetProjectRef,
    );
    const expectedConfirmation = [
      args.target,
      args.action,
      args.sourceSha,
      approvedPlan,
    ].join(":");
    if (applyConfirmation !== expectedConfirmation) {
      throw new RolloutControlError("apply_confirmation_mismatch");
    }

    const applied = await sql.begin(async (transaction) => {
      await transaction.unsafe(
        "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE",
      );
      await transaction.unsafe("SET LOCAL lock_timeout = '10s'");
      await transaction.unsafe("SET LOCAL statement_timeout = '30s'");
      await transaction.unsafe(`
        SELECT pg_catalog.PG_ADVISORY_XACT_LOCK(
          pg_catalog.HASHTEXTEXTENDED(
            'purchase-identity-rollout-control',
            0::BIGINT
          )
        )
      `);
      const existingRows = await transaction<Array<{ id: string }>>`
        SELECT operation.id::TEXT AS id
        FROM internal.purchase_identity_rollout_operations AS operation
        WHERE operation.id = ${args.operationId}::UUID
      `;
      if (existingRows.length > 1) {
        throw new RolloutControlError("invalid_apply_receipt");
      }

      if (existingRows.length === 0) {
        const snapshot = await inspectPurchaseIdentityRolloutSnapshot(
          transaction,
          true,
        );
        const currentPlan = buildPurchaseIdentityRolloutPlan(
          args,
          evidenceSha256,
          snapshot,
          targetProjectRef,
        );
        if (
          canonicalJSONString(currentPlan) !==
            canonicalJSONString(approvedPlanObject)
        ) {
          throw new RolloutControlError("approved_plan_mismatch");
        }
      } else {
        const liveSystemIdentifier = await inspectDatabaseSystemIdentifier(
          transaction,
        );
        if (
          liveSystemIdentifier !==
            approvedPlanObject.database_identity.system_identifier
        ) {
          throw new RolloutControlError("database_target_mismatch");
        }
      }
      const rows = await transaction<AppliedOperationRow[]>`
        SELECT *
        FROM internal.apply_purchase_identity_rollout_operation(
          ${args.operationId}::UUID,
          1,
          ${args.target},
          ${targetProjectRef},
          ${approvedPlanObject.database_identity.system_identifier},
          ${args.action},
          ${args.sourceSha},
          ${evidenceSha256},
          ${args.approvalSha256},
          ${approvedPlan},
          ${approvedPlanObject.before.principal_mode},
          ${approvedPlanObject.before.account_grant_mode},
          ${approvedPlanObject.before.minimum_client_protocol},
          ${approvedPlanObject.after.minimum_client_protocol},
          ${args.rollbackOf}::UUID
        )
      `;
      if (rows.length !== 1) {
        throw new RolloutControlError("invalid_apply_receipt");
      }
      const row = rows[0];
      if (
        row.operation_id.toLowerCase() !== args.operationId ||
        row.applied_action !== args.action ||
        row.principal_mode !== approvedPlanObject.after.principal_mode ||
        row.account_grant_mode !==
          approvedPlanObject.after.account_grant_mode ||
        Number(row.minimum_client_protocol) !==
          approvedPlanObject.after.minimum_client_protocol
      ) {
        throw new RolloutControlError("apply_receipt_mismatch");
      }
      return {
        plan: approvedPlanObject,
        planSha256: approvedPlan,
        alreadyApplied: row.already_applied,
      };
    });

    const summary: PurchaseIdentityRolloutSummary = {
      mode: "apply",
      plan_sha256: applied.planSha256,
      plan: applied.plan,
      applied: true,
      already_applied: applied.alreadyApplied,
    };
    await writePurchaseIdentityRolloutSummary(summary, args);
    return summary;
  } finally {
    await sql.end({ timeout: 5 });
  }
}

export function parsePurchaseIdentityRolloutEvidence(
  text: string,
): PurchaseIdentityRolloutEvidence {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new RolloutControlError("invalid_evidence_json");
  }
  if (!isObject(value)) {
    throw new RolloutControlError("invalid_evidence_shape");
  }
  assertExactKeys(value, [
    "schema_version",
    "source_sha",
    "reviewed_at",
    "artifacts",
    "candidate",
    "database",
    "ios",
    "revenuecat",
    "compatibility",
    "monitoring",
    "account_grants",
    "approval",
  ]);
  assertExactNestedKeys(value, "artifacts", [
    "candidate_validation_url",
    "backend_deploy_url",
    "ios_test_url",
    "physical_device_matrix_url",
    "revenuecat_matrix_url",
    "health_monitor_url",
  ]);
  assertExactNestedKeys(value, "candidate", [
    "validation",
    "exact_sha_deploy_smoke",
  ]);
  assertExactNestedKeys(value, "database", [
    "disposable_replay",
    "pgtap",
    "concurrency",
    "signout_rotation_concurrency",
    "lint",
    "security_advisor",
  ]);
  assertExactNestedKeys(value, "ios", [
    "unit_tests",
    "ui_tests",
    "clean_device_apple",
    "clean_device_google",
    "kill_relaunch",
    "keychain_unavailable",
    "offline_retry",
    "account_switch",
    "account_deletion",
    "signout_rotation_recovery",
    "signout_rotation_unrelated_session_rejection",
    "signout_rotation_entitlement_gate",
  ]);
  assertExactNestedKeys(value, "revenuecat", [
    "restore_behavior",
    "active_subscription",
    "renewal",
    "refund",
    "expiration",
    "lifetime",
    "seven_day_pass",
    "promotional_only",
    "mixed_storekit_promotion",
    "timeout_reconciliation",
    "duplicate_delivery",
    "attribute_scrub",
    "anonymous_app_user_id_count",
    "auth_rotation_receipt_sync_count",
    "auth_rotation_customer_transfer_count",
  ]);
  assertExactNestedKeys(value, "compatibility", [
    "old_client_new_backend",
    "legacy_handoff_retained",
    "stable_rollback_rehearsal",
    "live_rotation_rollback_support",
  ]);
  assertExactNestedKeys(value, "monitoring", [
    "required_principal_health",
    "required_signout_rotation_health",
    "signout_rotation_expiry_and_thresholds",
    "queue_and_lease_health",
  ]);
  assertExactNestedKeys(value, "account_grants", [
    "projection_divergence_count",
    "issuance_cutover",
    "authoritative_rollback_rehearsal",
  ]);
  assertExactNestedKeys(value, "approval", ["reference_sha256"]);
  return value as unknown as PurchaseIdentityRolloutEvidence;
}

export function validatePurchaseIdentityRolloutEvidence(
  evidence: PurchaseIdentityRolloutEvidence,
  args: PurchaseIdentityRolloutArgs,
  now: Date = new Date(),
): void {
  const reviewedAt = Date.parse(evidence.reviewed_at);
  if (
    evidence.schema_version !== 2 || evidence.source_sha !== args.sourceSha ||
    !SHA_1.test(evidence.source_sha) ||
    !Number.isFinite(reviewedAt) ||
    evidence.approval.reference_sha256 !== args.approvalSha256 ||
    !SHA_256.test(evidence.approval.reference_sha256)
  ) {
    throw new RolloutControlError("evidence_identity_mismatch");
  }
  if (reviewedAt > now.getTime() + MAX_EVIDENCE_FUTURE_SKEW_MS) {
    throw new RolloutControlError("evidence_timestamp_in_future");
  }
  if (now.getTime() - reviewedAt > MAX_EVIDENCE_AGE_MS) {
    throw new RolloutControlError("evidence_stale");
  }
  if (!Object.values(evidence.artifacts).every(isHTTPSURL)) {
    throw new RolloutControlError("invalid_evidence_artifact_url");
  }

  const statuses: unknown[] = [
    ...Object.values(evidence.candidate),
    ...Object.values(evidence.database),
    ...Object.values(evidence.ios),
    evidence.revenuecat.active_subscription,
    evidence.revenuecat.renewal,
    evidence.revenuecat.refund,
    evidence.revenuecat.expiration,
    evidence.revenuecat.lifetime,
    evidence.revenuecat.seven_day_pass,
    evidence.revenuecat.promotional_only,
    evidence.revenuecat.mixed_storekit_promotion,
    evidence.revenuecat.timeout_reconciliation,
    evidence.revenuecat.duplicate_delivery,
    evidence.revenuecat.attribute_scrub,
    ...Object.values(evidence.compatibility),
    ...Object.values(evidence.monitoring),
    evidence.account_grants.issuance_cutover,
    evidence.account_grants.authoritative_rollback_rehearsal,
  ];
  if (!statuses.every(isEvidenceStatus)) {
    throw new RolloutControlError("invalid_evidence_status");
  }

  const rollback = args.action.startsWith("rollback_");
  const commonRequired = [
    ...Object.values(evidence.candidate),
    ...Object.values(evidence.database),
    evidence.ios.unit_tests,
    evidence.ios.ui_tests,
    ...Object.values(evidence.compatibility),
    evidence.monitoring.required_principal_health,
    evidence.monitoring.required_signout_rotation_health,
  ];
  const enableRequired = [
    ...Object.values(evidence.ios),
    evidence.revenuecat.active_subscription,
    evidence.revenuecat.renewal,
    evidence.revenuecat.refund,
    evidence.revenuecat.expiration,
    evidence.revenuecat.lifetime,
    evidence.revenuecat.seven_day_pass,
    evidence.revenuecat.promotional_only,
    evidence.revenuecat.mixed_storekit_promotion,
    evidence.revenuecat.timeout_reconciliation,
    evidence.revenuecat.duplicate_delivery,
    evidence.revenuecat.attribute_scrub,
    ...Object.values(evidence.monitoring),
  ];
  if (
    !commonRequired.every((status) => status === "passed") ||
    (!rollback && !enableRequired.every((status) => status === "passed"))
  ) {
    throw new RolloutControlError("required_evidence_incomplete");
  }
  if (
    evidence.revenuecat.restore_behavior !==
      "transfer_to_new_app_user_id" ||
    (!rollback && (
      evidence.revenuecat.anonymous_app_user_id_count !== 0 ||
      evidence.revenuecat.auth_rotation_receipt_sync_count !== 0 ||
      evidence.revenuecat.auth_rotation_customer_transfer_count !== 0 ||
      evidence.account_grants.projection_divergence_count !== 0
    ))
  ) {
    throw new RolloutControlError("provider_or_projection_evidence_failed");
  }

  if (
    args.action === "enable_authoritative" ||
    args.action === "rollback_authoritative"
  ) {
    if (
      evidence.account_grants.issuance_cutover !== "passed" ||
      evidence.account_grants.authoritative_rollback_rehearsal !== "passed"
    ) {
      throw new RolloutControlError("account_grant_evidence_incomplete");
    }
  }
}

export function buildPurchaseIdentityRolloutPlan(
  args: PurchaseIdentityRolloutArgs,
  evidenceSha256: string,
  snapshot: PurchaseIdentityRolloutDatabaseSnapshot,
  targetProjectRef: string = projectRefForTarget(args.target),
): PurchaseIdentityRolloutPlan {
  if (!SHA_256.test(evidenceSha256)) {
    throw new RolloutControlError("invalid_evidence_digest");
  }
  const before = {
    principal_mode: snapshot.principal_mode,
    account_grant_mode: snapshot.account_grant_mode,
    minimum_client_protocol: snapshot.minimum_client_protocol,
  };
  const after = { ...before };

  switch (args.action) {
    case "enable_stable":
      if (
        before.principal_mode !== "legacy" ||
        before.account_grant_mode !== "dual_read" ||
        args.minimumClientProtocol < 3 ||
        args.minimumClientProtocol < before.minimum_client_protocol
      ) {
        throw new RolloutControlError("invalid_stable_cutover_state");
      }
      after.principal_mode = "stable";
      after.minimum_client_protocol = args.minimumClientProtocol;
      break;
    case "rollback_stable":
      if (
        before.principal_mode !== "stable" ||
        before.account_grant_mode !== "dual_read" ||
        args.minimumClientProtocol !== before.minimum_client_protocol
      ) {
        throw new RolloutControlError("invalid_stable_rollback_state");
      }
      after.principal_mode = "legacy";
      break;
    case "enable_authoritative":
      if (
        before.principal_mode !== "stable" ||
        before.account_grant_mode !== "dual_read" ||
        args.minimumClientProtocol !== before.minimum_client_protocol
      ) {
        throw new RolloutControlError("invalid_authoritative_cutover_state");
      }
      after.account_grant_mode = "authoritative";
      break;
    case "rollback_authoritative":
      if (
        before.principal_mode !== "stable" ||
        before.account_grant_mode !== "authoritative" ||
        args.minimumClientProtocol !== before.minimum_client_protocol
      ) {
        throw new RolloutControlError("invalid_authoritative_rollback_state");
      }
      after.account_grant_mode = "dual_read";
      break;
  }

  if (!args.action.startsWith("rollback_")) {
    const unhealthy = snapshot.stale_pending_principal_count > 0 ||
      snapshot.unbound_active_principal_count > 0 ||
      snapshot.legacy_due_count > 0 ||
      snapshot.legacy_expired_claim_count > 0 ||
      snapshot.principal_due_count > 0 ||
      snapshot.principal_expired_claim_count > 0;
    if (unhealthy) {
      throw new RolloutControlError("rollout_health_not_clean");
    }
  }

  const {
    database_system_identifier: _databaseSystemIdentifier,
    principal_mode: _principalMode,
    account_grant_mode: _accountGrantMode,
    minimum_client_protocol: _minimumClientProtocol,
    ...health
  } = snapshot;
  return {
    schema_version: 1,
    tool_version: 1,
    operation_id: args.operationId,
    action: args.action,
    target_environment: args.target,
    database_identity: {
      project_ref: targetProjectRef,
      system_identifier: snapshot.database_system_identifier,
    },
    source_sha: args.sourceSha,
    evidence_sha256: evidenceSha256,
    approval_sha256: args.approvalSha256,
    rollback_of: args.rollbackOf,
    before,
    after,
    health,
  };
}

export async function inspectPurchaseIdentityRolloutSnapshot(
  sql: Sql,
  lockConfig = false,
): Promise<PurchaseIdentityRolloutDatabaseSnapshot> {
  const databaseSystemIdentifier = await inspectDatabaseSystemIdentifier(sql);
  const lockClause = lockConfig ? " FOR UPDATE" : "";
  const configRows = await sql.unsafe<
    Array<{
      principal_mode: "legacy" | "stable";
      account_grant_mode: "dual_read" | "authoritative";
      minimum_client_protocol: number;
    }>
  >(`
    SELECT
      config.principal_mode,
      config.account_grant_mode,
      config.minimum_client_protocol
    FROM internal.purchase_identity_rollout_config AS config
    WHERE config.config_key = 'current'${lockClause}
  `);
  if (configRows.length !== 1) {
    throw new RolloutControlError("rollout_config_unavailable");
  }

  const healthRows = await sql.unsafe<
    Array<Record<string, number | string>>
  >(`
    SELECT
      (SELECT COUNT(*)::INTEGER
       FROM internal.purchase_principals AS principal
       WHERE principal.status = 'active') AS active_principal_count,
      (SELECT COUNT(*)::INTEGER
       FROM internal.purchase_principals AS principal
       WHERE principal.status = 'pending') AS pending_principal_count,
      (SELECT COUNT(*)::INTEGER
       FROM internal.purchase_principals AS principal
       WHERE principal.status = 'pending'
         AND principal.updated_at < pg_catalog.NOW() - INTERVAL '30 minutes')
        AS stale_pending_principal_count,
      (SELECT COUNT(*)::INTEGER
       FROM internal.purchase_principals AS principal
       LEFT JOIN internal.purchase_principal_bindings AS binding
         ON binding.purchase_principal_id = principal.id
       WHERE principal.status = 'active'
         AND binding.purchase_principal_id IS NULL)
        AS unbound_active_principal_count,
      (SELECT COUNT(*)::INTEGER
       FROM internal.revenuecat_reconciliation_queue AS queue
       WHERE queue.next_reconcile_at <= pg_catalog.NOW()
         AND queue.claim_token IS NULL) AS legacy_due_count,
      (SELECT COUNT(*)::INTEGER
       FROM internal.revenuecat_reconciliation_queue AS queue
       WHERE queue.claim_token IS NOT NULL
         AND queue.claim_expires_at <= pg_catalog.NOW())
        AS legacy_expired_claim_count,
      (SELECT COUNT(*)::INTEGER
       FROM internal.purchase_principal_reconciliation_queue AS queue
       WHERE queue.next_reconcile_at <= pg_catalog.NOW()
         AND queue.claim_token IS NULL) AS principal_due_count,
      (SELECT COUNT(*)::INTEGER
       FROM internal.purchase_principal_reconciliation_queue AS queue
       WHERE queue.claim_token IS NOT NULL
         AND queue.claim_expires_at <= pg_catalog.NOW())
        AS principal_expired_claim_count
  `);
  if (healthRows.length !== 1) {
    throw new RolloutControlError("rollout_health_unavailable");
  }
  const health = healthRows[0];
  return {
    database_system_identifier: databaseSystemIdentifier,
    ...configRows[0],
    active_principal_count: integerField(health, "active_principal_count"),
    pending_principal_count: integerField(health, "pending_principal_count"),
    stale_pending_principal_count: integerField(
      health,
      "stale_pending_principal_count",
    ),
    unbound_active_principal_count: integerField(
      health,
      "unbound_active_principal_count",
    ),
    legacy_due_count: integerField(health, "legacy_due_count"),
    legacy_expired_claim_count: integerField(
      health,
      "legacy_expired_claim_count",
    ),
    principal_due_count: integerField(health, "principal_due_count"),
    principal_expired_claim_count: integerField(
      health,
      "principal_expired_claim_count",
    ),
  };
}

export async function inspectDatabaseSystemIdentifier(
  sql: Sql,
): Promise<string> {
  const rows = await sql.unsafe<Array<{ system_identifier: string }>>(`
    SELECT control.system_identifier::TEXT AS system_identifier
    FROM pg_catalog.PG_CONTROL_SYSTEM() AS control
  `);
  const value = rows[0]?.system_identifier;
  if (rows.length !== 1 || !DATABASE_SYSTEM_IDENTIFIER.test(value ?? "")) {
    throw new RolloutControlError("database_identity_unavailable");
  }
  return value;
}

export function validateTargetDatabaseURL(
  target: string,
  databaseUrl: string,
): string {
  const projectRef = projectRefForTarget(target);
  let parsed: URL;
  try {
    parsed = new URL(databaseUrl);
  } catch {
    throw new RolloutControlError("invalid_database_url");
  }
  if (parsed.protocol !== "postgres:" && parsed.protocol !== "postgresql:") {
    throw new RolloutControlError("invalid_database_url");
  }
  const directHost = `db.${projectRef}.supabase.co`;
  const poolerUser = `postgres.${projectRef}`;
  if (
    parsed.hostname.toLowerCase() !== directHost ||
    decodeURIComponent(parsed.username).toLowerCase() !== "postgres"
  ) {
    const decodedUser = decodeURIComponent(parsed.username).toLowerCase();
    if (
      decodedUser !== poolerUser ||
      !parsed.hostname.toLowerCase().endsWith(".pooler.supabase.com")
    ) {
      throw new RolloutControlError("database_target_mismatch");
    }
  }
  return projectRef;
}

function projectRefForTarget(target: string): string {
  const projectRef = TARGET_PROJECT_REFS[target];
  if (projectRef === undefined) {
    throw new RolloutControlError("unknown_target");
  }
  return projectRef;
}

export function parseApprovedPlanSummary(
  text: string,
): PurchaseIdentityRolloutSummary {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new RolloutControlError("invalid_approved_plan_json");
  }
  if (!isObject(value)) {
    throw new RolloutControlError("invalid_approved_plan_shape");
  }
  assertExactKeys(value, [
    "mode",
    "plan_sha256",
    "plan",
    "applied",
    "already_applied",
  ]);
  if (!isObject(value.plan)) {
    throw new RolloutControlError("invalid_approved_plan_shape");
  }
  return value as unknown as PurchaseIdentityRolloutSummary;
}

export async function validateApprovedPlanSummary(
  summary: PurchaseIdentityRolloutSummary,
  args: PurchaseIdentityRolloutArgs,
  evidenceSha256: string,
  targetProjectRef: string,
): Promise<PurchaseIdentityRolloutPlan> {
  const plan = summary.plan;
  if (
    summary.mode !== "dry_run" || summary.applied !== false ||
    summary.already_applied !== false ||
    summary.plan_sha256 !== args.approvedPlanSha256 ||
    !isObject(plan) || !isObject(plan.database_identity) ||
    !isObject(plan.before) || !isObject(plan.after) ||
    !isObject(plan.health)
  ) {
    throw new RolloutControlError("invalid_approved_plan_shape");
  }
  const computedDigest = await sha256(canonicalJSONString(plan));
  if (
    computedDigest !== summary.plan_sha256 ||
    plan.schema_version !== 1 || plan.tool_version !== 1 ||
    plan.operation_id !== args.operationId ||
    plan.action !== args.action ||
    plan.target_environment !== args.target ||
    plan.database_identity.project_ref !== targetProjectRef ||
    !DATABASE_SYSTEM_IDENTIFIER.test(
      plan.database_identity.system_identifier,
    ) ||
    plan.source_sha !== args.sourceSha ||
    plan.evidence_sha256 !== evidenceSha256 ||
    plan.approval_sha256 !== args.approvalSha256 ||
    plan.rollback_of !== args.rollbackOf
  ) {
    throw new RolloutControlError("approved_plan_mismatch");
  }
  return plan;
}

export function assertCheckedOutSourceState(
  expectedSha: string,
  actualSha: string,
  sourceStatus: string,
): void {
  if (actualSha.trim().toLowerCase() !== expectedSha) {
    throw new RolloutControlError("source_sha_checkout_mismatch");
  }
  if (sourceStatus.trim().length > 0) {
    throw new RolloutControlError("source_checkout_dirty");
  }
}

export async function verifyCheckedOutSourceSha(
  expectedSha: string,
): Promise<void> {
  const topLevel = await new Deno.Command("git", {
    args: ["rev-parse", "--show-toplevel"],
    stdout: "piped",
    stderr: "null",
  }).output();
  if (!topLevel.success) {
    throw new RolloutControlError("source_checkout_unavailable");
  }
  const repositoryRoot = new TextDecoder().decode(topLevel.stdout).trim();
  if (repositoryRoot.length === 0) {
    throw new RolloutControlError("source_checkout_unavailable");
  }
  const revision = await new Deno.Command("git", {
    cwd: repositoryRoot,
    args: ["rev-parse", "HEAD"],
    stdout: "piped",
    stderr: "null",
  }).output();
  const status = await new Deno.Command("git", {
    cwd: repositoryRoot,
    args: [
      "status",
      "--porcelain=v1",
      "--untracked-files=all",
      "--",
      ".",
    ],
    stdout: "piped",
    stderr: "null",
  }).output();
  if (!revision.success || !status.success) {
    throw new RolloutControlError("source_checkout_unavailable");
  }
  assertCheckedOutSourceState(
    expectedSha,
    new TextDecoder().decode(revision.stdout),
    new TextDecoder().decode(status.stdout),
  );
}

export function canonicalJSONString(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function writePurchaseIdentityRolloutSummary(
  summary: PurchaseIdentityRolloutSummary,
  args: PurchaseIdentityRolloutArgs,
): Promise<void> {
  await Deno.writeTextFile(
    args.summaryJsonPath,
    `${JSON.stringify(summary, null, 2)}\n`,
  );
  await Deno.writeTextFile(
    args.summaryMarkdownPath,
    [
      "# Purchase identity rollout control",
      "",
      `- Mode: \`${summary.mode}\``,
      `- Action: \`${summary.plan.action}\``,
      `- Target: \`${summary.plan.target_environment}\``,
      `- Source SHA: \`${summary.plan.source_sha}\``,
      `- Plan SHA-256: \`${summary.plan_sha256}\``,
      `- Applied: \`${summary.applied}\``,
      `- Already applied: \`${summary.already_applied}\``,
      `- Principal mode: \`${summary.plan.before.principal_mode}\` → \`${summary.plan.after.principal_mode}\``,
      `- Account-grant mode: \`${summary.plan.before.account_grant_mode}\` → \`${summary.plan.after.account_grant_mode}\``,
      `- Minimum client protocol: \`${summary.plan.before.minimum_client_protocol}\` → \`${summary.plan.after.minimum_client_protocol}\``,
      "",
    ].join("\n"),
  );
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (!isObject(value)) return value;
  return Object.fromEntries(
    Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]),
  );
}

function assertExactNestedKeys(
  value: Record<string, unknown>,
  key: string,
  expected: string[],
): void {
  const nested = value[key];
  if (!isObject(nested)) {
    throw new RolloutControlError("invalid_evidence_shape");
  }
  assertExactKeys(nested, expected);
}

function assertExactKeys(
  value: Record<string, unknown>,
  expected: string[],
): void {
  const actual = Object.keys(value).sort();
  const required = [...expected].sort();
  if (JSON.stringify(actual) !== JSON.stringify(required)) {
    throw new RolloutControlError("unexpected_evidence_fields");
  }
}

function integerField(
  row: Record<string, number | string>,
  key: string,
): number {
  const value = Number(row[key]);
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RolloutControlError("invalid_health_snapshot");
  }
  return value;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isEvidenceStatus(value: unknown): value is EvidenceStatus {
  return value === "passed" || value === "pending";
}

function isHTTPSURL(value: unknown): boolean {
  if (typeof value !== "string" || value.length > 2048) return false;
  try {
    const url = new URL(value);
    const hostname = url.hostname.toLowerCase();
    return url.protocol === "https:" &&
      url.username.length === 0 &&
      url.password.length === 0 &&
      hostname.length > 0 &&
      hostname !== "localhost" &&
      hostname !== "invalid" &&
      !hostname.endsWith(".invalid");
  } catch {
    return false;
  }
}

function isRolloutAction(
  value: string,
): value is PurchaseIdentityRolloutAction {
  return [
    "enable_stable",
    "rollback_stable",
    "enable_authoritative",
    "rollback_authoritative",
  ].includes(value);
}

function requiredValue(values: Map<string, string>, key: string): string {
  const value = values.get(key);
  if (!value) throw new RolloutControlError("missing_required_argument");
  return value;
}

function requiredEnv(key: string): string {
  const value = Deno.env.get(key)?.trim() ?? "";
  if (!value) throw new RolloutControlError("missing_database_url");
  return value;
}

function safeErrorCode(error: unknown): string {
  if (error instanceof RolloutControlError) return error.code;
  const candidate = error instanceof Error ? error.name : typeof error;
  return /^[A-Za-z][A-Za-z0-9]{0,63}$/.test(candidate)
    ? candidate
    : "OperationError";
}

class RolloutControlError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "RolloutControlError";
    this.code = /^[a-z][a-z0-9_]{0,63}$/.test(code)
      ? code
      : "rollout_control_failed";
  }
}
