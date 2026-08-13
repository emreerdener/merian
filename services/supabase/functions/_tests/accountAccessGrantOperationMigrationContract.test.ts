import { assert, assertEquals, assertMatch } from "@std/assert";

const migrationPath = new URL(
  "../../migrations/20260813131735_add_account_access_grant_operation_receipts.sql",
  import.meta.url,
);
const toolPath = new URL(
  "../../scripts/grant_account_access_entitlements.ts",
  import.meta.url,
);
const legacyToolPath = new URL(
  "../../scripts/grant_revenuecat_beta_entitlements.ts",
  import.meta.url,
);

Deno.test("account grant operation receipts are private and immutable", async () => {
  const migration = await Deno.readTextFile(migrationPath);
  for (
    const required of [
      "CREATE TABLE internal.account_access_grant_operations",
      "id UUID PRIMARY KEY",
      "plan_sha256 TEXT NOT NULL UNIQUE",
      "candidate_set_sha256 TEXT NOT NULL",
      "candidate_count BETWEEN 1 AND 500",
      "ALTER TABLE internal.account_access_grant_operations ENABLE ROW LEVEL SECURITY",
      "ALTER TABLE internal.account_access_grant_operations FORCE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.account_access_grant_operations",
      "FROM PUBLIC, anon, authenticated, service_role",
      "CREATE OR REPLACE FUNCTION internal.reject_account_access_grant_operation_mutation()",
      "BEFORE UPDATE OR DELETE ON internal.account_access_grant_operations",
      "account_access_grant_operation_immutable",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assert(
      migration.includes(required),
      `Account grant operation migration is missing: ${required}`,
    );
  }
  assertEquals(
    /^\s*GRANT\b[^;]*account_access_grant_operations/im.test(migration),
    false,
  );
  assertEquals(/\bBEGIN\s*;/i.test(migration), false);
  assertEquals(/\bCOMMIT\s*;/i.test(migration), false);
  assertEquals(/\bSET\s+LOCAL\b/i.test(migration), false);
});

Deno.test("account grant apply is exact-plan, identity-safe, and RevenueCat-free", async () => {
  const tool = await Deno.readTextFile(toolPath);
  for (
    const required of [
      "verifyCheckedOutSourceSha(args.sourceSha)",
      "validateTargetDatabaseURL(args.target, databaseUrl)",
      "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE",
      "PG_ADVISORY_XACT_LOCK",
      "internal.account_access_grant_operations",
      "public.record_account_access_grant(",
      "approved_plan_mismatch",
      "apply_confirmation_mismatch",
      "database_target_mismatch",
      "candidateSetSha256",
      "Neither stdout nor the retained plan contains account identifiers",
    ]
  ) {
    assert(
      tool.includes(required),
      `Account grant tool is missing: ${required}`,
    );
  }
  assertEquals(tool.includes("REVENUECAT_SECRET_API_KEY"), false);
  assertEquals(tool.includes("api.revenuecat.com"), false);
  assertEquals(tool.includes("app_user_id"), true);
  assertMatch(
    tool,
    /selection\.candidates\.map[\s\S]*candidate\.app_user_id\.toLowerCase\(\)/,
  );
  const receiptLookup = tool.indexOf("const receiptRows");
  const liveConfigLock = tool.indexOf("const liveSnapshot", receiptLookup);
  assert(
    receiptLookup >= 0 && liveConfigLock > receiptLookup,
    "Exact receipt replay must be checked before mutable rollout modes.",
  );

  const legacy = await Deno.readTextFile(legacyToolPath);
  assert(
    legacy.includes("legacy_revenuecat_promotion_apply_retired"),
    "Legacy RevenueCat promotion apply must fail closed after ledger issuance exists.",
  );
});
