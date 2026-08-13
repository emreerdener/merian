import { assert, assertEquals } from "@std/assert";

const migration = normalized(
  await Deno.readTextFile(
    new URL(
      "../../migrations/20260813040000_add_purchase_identity_rollout_control.sql",
      import.meta.url,
    ),
  ),
);
const baseMigration = normalized(
  await Deno.readTextFile(
    new URL(
      "../../migrations/20260812144948_introduce_stable_purchase_principals.sql",
      import.meta.url,
    ),
  ),
);
const tool = normalized(
  await Deno.readTextFile(
    new URL(
      "../../scripts/control_purchase_identity_rollout.ts",
      import.meta.url,
    ),
  ),
);

Deno.test("purchase identity rollout remains default-off and gains an owner-only ledger", () => {
  for (
    const fragment of [
      "principal_mode text not null default 'legacy'",
      "account_grant_mode text not null default 'dual_read'",
      "values ('current', 'legacy', 'dual_read', 1)",
    ]
  ) {
    assert(
      baseMigration.includes(fragment),
      `missing default-off: ${fragment}`,
    );
  }
  for (
    const fragment of [
      "create table internal.purchase_identity_rollout_operations",
      "alter table internal.purchase_identity_rollout_operations enable row level security",
      "revoke all on table internal.purchase_identity_rollout_operations from public, anon, authenticated, service_role",
      "source_sha text not null check (source_sha ~ '^[0-9a-f]{40}$')",
      "target_project_ref text not null",
      "database_system_identifier text not null",
      "constraint purchase_identity_rollout_target_binding check",
      "target_environment = 'production' and target_project_ref = 'qlarqavoqhkuwzmevrmf'",
      "approved_plan_sha256 text not null unique",
      "constraint purchase_identity_rollout_one_axis check",
      "rollback_of uuid unique references internal.purchase_identity_rollout_operations(id)",
    ]
  ) {
    assert(
      migration.includes(fragment),
      `missing ledger contract: ${fragment}`,
    );
  }
});

Deno.test("rollout mutation is owner-only, replay-safe, and changes one axis", () => {
  for (
    const fragment of [
      "create or replace function internal.apply_purchase_identity_rollout_operation(",
      "security invoker",
      "set search_path = ''",
      "if session_user <> 'postgres' or current_user <> 'postgres' then",
      "purchase_identity_rollout_owner_required",
      "from pg_catalog.pg_control_system() as control",
      "purchase_identity_rollout_database_target_mismatch",
      "pg_catalog.pg_advisory_xact_lock(",
      "purchase-identity-rollout-control",
      "from internal.purchase_identity_rollout_config as config where config.config_key = 'current' for update",
      "purchase_identity_rollout_replay_mismatch",
      "purchase_identity_rollout_state_changed",
      "when 'enable_stable' then",
      "when 'rollback_stable' then",
      "when 'enable_authoritative' then",
      "when 'rollback_authoritative' then",
      "purchase_identity_rollout_rollback_reference_required",
      "rollback_source.target_project_ref <> p_target_project_ref",
      "rollback_source.database_system_identifier <> p_database_system_identifier",
      "rollback_source.minimum_client_protocol_after <> rollout.minimum_client_protocol",
      "insert into internal.purchase_identity_rollout_operations",
      "revoke all on function internal.apply_purchase_identity_rollout_operation(",
      ") from public, anon, authenticated, service_role",
    ]
  ) {
    assert(
      migration.includes(fragment),
      `missing mutation contract: ${fragment}`,
    );
  }
  assertEquals(
    /grant\s+execute\s+on\s+function\s+internal\.apply_purchase_identity_rollout_operation/
      .test(
        migration,
      ),
    false,
  );
  assert(
    migration.indexOf("pg_catalog.pg_advisory_xact_lock(") <
      migration.indexOf(
        "from internal.purchase_identity_rollout_operations as operation where operation.id = p_operation_id",
      ),
    "The global rollout lock must precede receipt replay lookup.",
  );
});

Deno.test("rollout tool is dry-run-first and binds apply to exact evidence", () => {
  for (
    const fragment of [
      'mode: "dry_run"',
      "approved_plan_required",
      "approved_plan_json",
      "apply_confirmation_mismatch",
      "approved_plan_mismatch",
      "database_target_mismatch",
      "evidence_stale",
      'args: ["rev-parse", "--show-toplevel"]',
      "cwd: repositoryroot",
      "pg_catalog.pg_advisory_xact_lock(",
      "purchase-identity-rollout-control",
      "merian_purchase_identity_rollout_apply_confirmation",
      "candidate_validation_url",
      "physical_device_matrix_url",
      "revenuecat_matrix_url",
      "transfer_to_new_app_user_id",
      "anonymous_app_user_id_count !== 0",
      "auth_rotation_receipt_sync_count !== 0",
      "auth_rotation_customer_transfer_count !== 0",
      "projection_divergence_count !== 0",
      "required_principal_health",
      "rollout_health_not_clean",
    ]
  ) {
    assert(tool.includes(fragment), `missing tool contract: ${fragment}`);
  }
});

function normalized(value: string): string {
  return value.replaceAll(/\s+/g, " ").trim().toLowerCase();
}
