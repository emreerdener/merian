import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  assertCheckedOutSourceState,
  buildPurchaseIdentityRolloutPlan,
  canonicalJSONString,
  parseApprovedPlanSummary,
  parsePurchaseIdentityRolloutArgs,
  parsePurchaseIdentityRolloutEvidence,
  PurchaseIdentityRolloutArgs,
  PurchaseIdentityRolloutDatabaseSnapshot,
  PurchaseIdentityRolloutEvidence,
  sha256,
  validateApprovedPlanSummary,
  validatePurchaseIdentityRolloutEvidence,
  validateTargetDatabaseURL,
} from "./control_purchase_identity_rollout.ts";

const SOURCE_SHA = "a".repeat(40);
const APPROVAL_SHA = "b".repeat(64);
const EVIDENCE_SHA = "c".repeat(64);
const PLAN_SHA = "d".repeat(64);
const OPERATION_ID = "11111111-1111-4111-8111-111111111111";
const ROLLBACK_ID = "22222222-2222-4222-8222-222222222222";

Deno.test("rollout CLI defaults to dry-run and apply requires an approved digest", () => {
  const dryRun = parsePurchaseIdentityRolloutArgs(baseCLI());
  assertEquals(dryRun.apply, false);
  assertEquals(dryRun.approvedPlanSha256, null);

  assertThrows(
    () => parsePurchaseIdentityRolloutArgs([...baseCLI(), "--apply"]),
    Error,
    "approved_plan_required",
  );
  const apply = parsePurchaseIdentityRolloutArgs([
    ...baseCLI(),
    "--apply",
    "--approved-plan-sha256",
    PLAN_SHA,
    "--approved-plan-json",
    "approved-plan.json",
  ]);
  assertEquals(apply.apply, true);
  assertEquals(apply.approvedPlanSha256, PLAN_SHA);
  assertEquals(apply.approvedPlanJsonPath, "approved-plan.json");
});

Deno.test("rollout CLI requires an explicit rollback operation reference", () => {
  const args = baseCLI();
  args[1] = "rollback_stable";
  assertThrows(
    () => parsePurchaseIdentityRolloutArgs(args),
    Error,
    "invalid_rollback_reference",
  );
  const parsed = parsePurchaseIdentityRolloutArgs([
    ...args,
    "--rollback-of",
    ROLLBACK_ID,
  ]);
  assertEquals(parsed.rollbackOf, ROLLBACK_ID);
});

Deno.test("evidence parser rejects unknown fields and cutover requires every external gate", () => {
  const evidence = completeEvidence();
  const parsed = parsePurchaseIdentityRolloutEvidence(
    JSON.stringify(evidence),
  );
  validatePurchaseIdentityRolloutEvidence(parsed, baseArgs());

  const unknown = { ...evidence, customer_id: "must-not-be-accepted" };
  assertThrows(
    () => parsePurchaseIdentityRolloutEvidence(JSON.stringify(unknown)),
    Error,
    "unexpected_evidence_fields",
  );

  evidence.artifacts.candidate_validation_url =
    "https://replace.invalid/candidate-validation";
  assertThrows(
    () => validatePurchaseIdentityRolloutEvidence(evidence, baseArgs()),
    Error,
    "invalid_evidence_artifact_url",
  );
  evidence.artifacts.candidate_validation_url =
    "https://operator:secret@artifacts.merian.app/candidate-validation";
  assertThrows(
    () => validatePurchaseIdentityRolloutEvidence(evidence, baseArgs()),
    Error,
    "invalid_evidence_artifact_url",
  );
  evidence.artifacts.candidate_validation_url =
    "https://artifacts.merian.app/candidate-validation";

  evidence.ios.kill_relaunch = "pending";
  assertThrows(
    () => validatePurchaseIdentityRolloutEvidence(evidence, baseArgs()),
    Error,
    "required_evidence_incomplete",
  );

  evidence.ios.kill_relaunch = "passed";
  evidence.reviewed_at = "2026-08-10T00:00:00.000Z";
  assertThrows(
    () =>
      validatePurchaseIdentityRolloutEvidence(
        evidence,
        baseArgs(),
        new Date("2026-08-12T00:00:01.000Z"),
      ),
    Error,
    "evidence_stale",
  );
});

Deno.test("stable cutover changes only principal mode and minimum protocol", () => {
  const plan = buildPurchaseIdentityRolloutPlan(
    baseArgs(),
    EVIDENCE_SHA,
    cleanLegacySnapshot(),
  );
  assertEquals(plan.before, {
    principal_mode: "legacy",
    account_grant_mode: "dual_read",
    minimum_client_protocol: 1,
  });
  assertEquals(plan.after, {
    principal_mode: "stable",
    account_grant_mode: "dual_read",
    minimum_client_protocol: 2,
  });
});

Deno.test("cutover fails on queue or lease debt while rollback remains available", () => {
  const unhealthy = cleanLegacySnapshot();
  unhealthy.principal_expired_claim_count = 1;
  assertThrows(
    () => buildPurchaseIdentityRolloutPlan(baseArgs(), EVIDENCE_SHA, unhealthy),
    Error,
    "rollout_health_not_clean",
  );

  const rollbackArgs = baseArgs({
    action: "rollback_stable",
    rollbackOf: ROLLBACK_ID,
  });
  const rollbackEvidence = completeEvidence();
  rollbackEvidence.monitoring.queue_and_lease_health = "pending";
  rollbackEvidence.ios.clean_device_apple = "pending";
  rollbackEvidence.revenuecat.refund = "pending";
  rollbackEvidence.revenuecat.anonymous_app_user_id_count = -1;
  rollbackEvidence.account_grants.projection_divergence_count = -1;
  validatePurchaseIdentityRolloutEvidence(
    rollbackEvidence,
    rollbackArgs,
  );
  const stableSnapshot: PurchaseIdentityRolloutDatabaseSnapshot = {
    ...unhealthy,
    principal_mode: "stable",
    minimum_client_protocol: 2,
  };
  const plan = buildPurchaseIdentityRolloutPlan(
    rollbackArgs,
    EVIDENCE_SHA,
    stableSnapshot,
  );
  assertEquals(plan.after.principal_mode, "legacy");
  assertEquals(plan.after.minimum_client_protocol, 2);
});

Deno.test("account-grant authority requires issuance and rollback evidence", () => {
  const args = baseArgs({
    action: "enable_authoritative",
    minimumClientProtocol: 2,
  });
  const evidence = completeEvidence();
  evidence.account_grants.issuance_cutover = "pending";
  evidence.account_grants.authoritative_rollback_rehearsal = "pending";
  assertThrows(
    () => validatePurchaseIdentityRolloutEvidence(evidence, args),
    Error,
    "account_grant_evidence_incomplete",
  );

  evidence.account_grants.issuance_cutover = "passed";
  evidence.account_grants.authoritative_rollback_rehearsal = "passed";
  validatePurchaseIdentityRolloutEvidence(evidence, args);
  const plan = buildPurchaseIdentityRolloutPlan(
    args,
    EVIDENCE_SHA,
    {
      ...cleanLegacySnapshot(),
      principal_mode: "stable",
      minimum_client_protocol: 2,
    },
  );
  assertEquals(plan.after.account_grant_mode, "authoritative");
  assertEquals(plan.after.principal_mode, "stable");
});

Deno.test("canonical plan digest is stable across object key order", async () => {
  const first = canonicalJSONString({ b: 2, a: { d: 4, c: 3 } });
  const second = canonicalJSONString({ a: { c: 3, d: 4 }, b: 2 });
  assertEquals(first, second);
  assertEquals(await sha256(first), await sha256(second));
});

Deno.test("rollout target is bound to the reviewed Supabase project", () => {
  assertEquals(
    validateTargetDatabaseURL(
      "production",
      "postgresql://postgres:secret@db.qlarqavoqhkuwzmevrmf.supabase.co:5432/postgres",
    ),
    "qlarqavoqhkuwzmevrmf",
  );
  assertEquals(
    validateTargetDatabaseURL(
      "production",
      "postgresql://postgres.qlarqavoqhkuwzmevrmf:secret@aws-0-us-east-1.pooler.supabase.com:6543/postgres",
    ),
    "qlarqavoqhkuwzmevrmf",
  );
  assertThrows(
    () =>
      validateTargetDatabaseURL(
        "production",
        "postgresql://postgres:secret@db.wrongprojectref00000.supabase.co:5432/postgres",
      ),
    Error,
    "database_target_mismatch",
  );
  assertThrows(
    () => validateTargetDatabaseURL("staging", "postgresql://localhost/db"),
    Error,
    "unknown_target",
  );
});

Deno.test("approved dry-run plan is replayable and exact-digest bound", async () => {
  const dryArgs = baseArgs();
  const plan = buildPurchaseIdentityRolloutPlan(
    dryArgs,
    EVIDENCE_SHA,
    cleanLegacySnapshot(),
  );
  const digest = await sha256(canonicalJSONString(plan));
  const applyArgs = baseArgs({
    apply: true,
    approvedPlanSha256: digest,
    approvedPlanJsonPath: "approved-plan.json",
  });
  const parsed = parseApprovedPlanSummary(JSON.stringify({
    mode: "dry_run",
    plan_sha256: digest,
    plan,
    applied: false,
    already_applied: false,
  }));
  assertEquals(
    await validateApprovedPlanSummary(
      parsed,
      applyArgs,
      EVIDENCE_SHA,
      "qlarqavoqhkuwzmevrmf",
    ),
    plan,
  );

  const wrong = { ...parsed, plan_sha256: PLAN_SHA };
  await assertRejects(
    () =>
      validateApprovedPlanSummary(
        wrong,
        { ...applyArgs, approvedPlanSha256: PLAN_SHA },
        EVIDENCE_SHA,
        "qlarqavoqhkuwzmevrmf",
      ),
    Error,
    "approved_plan_mismatch",
  );
});

Deno.test("source checkout must match the exact SHA and contain no source edits", () => {
  assertCheckedOutSourceState(SOURCE_SHA, `${SOURCE_SHA}\n`, "");
  assertThrows(
    () => assertCheckedOutSourceState(SOURCE_SHA, "f".repeat(40), ""),
    Error,
    "source_sha_checkout_mismatch",
  );
  assertThrows(
    () => assertCheckedOutSourceState(SOURCE_SHA, SOURCE_SHA, " M source.ts"),
    Error,
    "source_checkout_dirty",
  );
});

Deno.test("sha helper rejects no promises and returns lowercase digest", async () => {
  const digest = await sha256("merian-purchase-identity");
  assertEquals(/^[0-9a-f]{64}$/.test(digest), true);
  await assertRejects(
    async () => {
      const args = baseArgs();
      args.evidenceJsonPath = "/definitely/missing/evidence.json";
      await Deno.readTextFile(args.evidenceJsonPath);
    },
    Error,
  );
});

function baseCLI(): string[] {
  return [
    "--action",
    "enable_stable",
    "--target",
    "production",
    "--source-sha",
    SOURCE_SHA,
    "--minimum-client-protocol",
    "2",
    "--evidence-json",
    "evidence.json",
    "--operation-id",
    OPERATION_ID,
    "--approval-sha256",
    APPROVAL_SHA,
    "--summary-json",
    "summary.json",
    "--summary-markdown",
    "summary.md",
  ];
}

function baseArgs(
  overrides: Partial<PurchaseIdentityRolloutArgs> = {},
): PurchaseIdentityRolloutArgs {
  return {
    action: "enable_stable",
    target: "production",
    sourceSha: SOURCE_SHA,
    minimumClientProtocol: 2,
    evidenceJsonPath: "evidence.json",
    operationId: OPERATION_ID,
    approvalSha256: APPROVAL_SHA,
    rollbackOf: null,
    summaryJsonPath: "summary.json",
    summaryMarkdownPath: "summary.md",
    apply: false,
    approvedPlanSha256: null,
    approvedPlanJsonPath: null,
    ...overrides,
  };
}

function cleanLegacySnapshot(): PurchaseIdentityRolloutDatabaseSnapshot {
  return {
    database_system_identifier: "1234567890123456789",
    principal_mode: "legacy",
    account_grant_mode: "dual_read",
    minimum_client_protocol: 1,
    active_principal_count: 0,
    pending_principal_count: 0,
    stale_pending_principal_count: 0,
    unbound_active_principal_count: 0,
    legacy_due_count: 0,
    legacy_expired_claim_count: 0,
    principal_due_count: 0,
    principal_expired_claim_count: 0,
  };
}

function completeEvidence(): PurchaseIdentityRolloutEvidence {
  return {
    schema_version: 1,
    source_sha: SOURCE_SHA,
    reviewed_at: new Date().toISOString(),
    artifacts: {
      candidate_validation_url: "https://evidence.example/candidate",
      backend_deploy_url: "https://evidence.example/deploy",
      ios_test_url: "https://evidence.example/ios-tests",
      physical_device_matrix_url: "https://evidence.example/devices",
      revenuecat_matrix_url: "https://evidence.example/revenuecat",
      health_monitor_url: "https://evidence.example/health",
    },
    candidate: {
      validation: "passed",
      exact_sha_deploy_smoke: "passed",
    },
    database: {
      disposable_replay: "passed",
      pgtap: "passed",
      concurrency: "passed",
      lint: "passed",
      security_advisor: "passed",
    },
    ios: {
      unit_tests: "passed",
      ui_tests: "passed",
      clean_device_apple: "passed",
      clean_device_google: "passed",
      kill_relaunch: "passed",
      keychain_unavailable: "passed",
      offline_retry: "passed",
      account_switch: "passed",
      account_deletion: "passed",
    },
    revenuecat: {
      restore_behavior: "transfer_to_new_app_user_id",
      active_subscription: "passed",
      renewal: "passed",
      refund: "passed",
      expiration: "passed",
      lifetime: "passed",
      seven_day_pass: "passed",
      promotional_only: "passed",
      mixed_storekit_promotion: "passed",
      timeout_reconciliation: "passed",
      duplicate_delivery: "passed",
      attribute_scrub: "passed",
      anonymous_app_user_id_count: 0,
      auth_rotation_receipt_sync_count: 0,
      auth_rotation_customer_transfer_count: 0,
    },
    compatibility: {
      old_client_new_backend: "passed",
      legacy_handoff_retained: "passed",
      stable_rollback_rehearsal: "passed",
    },
    monitoring: {
      required_principal_health: "passed",
      queue_and_lease_health: "passed",
    },
    account_grants: {
      projection_divergence_count: 0,
      issuance_cutover: "pending",
      authoritative_rollback_rehearsal: "pending",
    },
    approval: {
      reference_sha256: APPROVAL_SHA,
    },
  };
}
