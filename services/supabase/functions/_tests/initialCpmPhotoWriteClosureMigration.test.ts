import { assert } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261029180156_prepare_initial_cpm_photo_write_closure.sql",
    import.meta.url,
  ),
);

Deno.test("CPM closure remains uninstalled database-owner metadata", () => {
  assert(!/GRANT\s|CREATE(?: OR REPLACE)? FUNCTION public\./i.test(sql));
  assert(
    !sql.includes("INSERT INTO internal.initial_cpm_photo_write_policies"),
  );
  for (const name of ["write_policies", "write_closures"]) {
    assert(
      sql.includes(
        `ALTER TABLE internal.initial_cpm_photo_${name} ENABLE ROW LEVEL SECURITY`,
      ),
    );
    assert(
      sql.includes(
        `REVOKE ALL ON internal.initial_cpm_photo_${name} FROM PUBLIC,anon,authenticated,service_role`,
      ),
    );
  }
  assert(!sql.includes("SET state='released'"));
  assert(!sql.includes("SET marker_confirmed"));
});

Deno.test("CPM closure preserves prior policy binding and exact stale-claim denial", () => {
  for (
    const clause of [
      "OLD.state='bound' AND OLD.write_policy_digest IS NULL",
      "a.write_policy_digest IS DISTINCT FROM NEW.policy_digest",
      "NEW.observed_at<a.issued_at",
      "r.claim_expires_at<=clock_timestamp()",
      "NEW.claim_digest IS DISTINCT FROM",
      "saved.observed_at IS DISTINCT FROM p_observed_at",
      "saved.claim_digest IS DISTINCT FROM claim_hash",
      "WHERE state='may_have_issued' AND NOT write_closed",
      "internal.assert_initial_preparation_unfunded(owner_id,a.scan_id)",
    ]
  ) assert(sql.includes(clause), clause);
  const table =
    sql.split("CREATE TABLE internal.initial_cpm_photo_write_closures(")[1]
      .split(");")[0];
  assert(!/owner_id|byte_count|sha256|content_type|claim_token/.test(table));
});

Deno.test("CPM closure acquires capacity before registry and attempt locks", () => {
  const guard = sql.split(
    "CREATE FUNCTION internal.guard_initial_cpm_photo_write_closure()",
  )[1].split("END; $$;")[0];
  const capacity = guard.indexOf(
    "PERFORM internal.lock_initial_cpm_photo_capacity()",
  );
  const registry = guard.indexOf("WHERE object_id=a.object_id FOR UPDATE");
  const attempt = guard.indexOf("WHERE attempt_id=NEW.attempt_id FOR UPDATE");
  assert(capacity >= 0 && capacity < registry && registry < attempt);
  assert(!guard.includes("lock_initial_preparation_scope"));
});

Deno.test("raw policy-bound issuance locks exact backend eligibility", () => {
  const branch = sql.split(
    "IF TG_OP='UPDATE' AND OLD.state='bound' AND NEW.state='may_have_issued' AND OLD.write_policy_digest IS NOT NULL THEN",
  )[1].split("END IF;")[0];
  for (
    const clause of [
      "internal.initial_preparation_backend_eligibility",
      "b.state='eligible'",
      "b.configuration_digest=OLD.backend_configuration_digest",
      "FOR SHARE OF p,b NOWAIT",
    ]
  ) assert(branch.includes(clause), clause);
});
