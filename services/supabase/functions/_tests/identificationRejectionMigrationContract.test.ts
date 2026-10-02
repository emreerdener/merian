import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261001144039_add_identification_rejection_authority.sql",
    import.meta.url,
  ),
);
Deno.test("identification rejection keeps raw history owner-private and mutations service-only", () => {
  assertStringIncludes(
    sql,
    "REVOKE SELECT ON public.scans FROM anon, authenticated",
  );
  assertStringIncludes(sql, "attname <> 'ai_identification_review'");
  assertStringIncludes(sql, "scan.user_id = (SELECT auth.uid())");
  assertStringIncludes(
    sql,
    "pg_catalog.CARDINALITY(p_scan_ids) NOT BETWEEN 1 AND 100",
  );
  assertStringIncludes(sql, "PERFORM internal.require_service_role()");
  assert(!/GRANT\s+(?:INSERT|UPDATE)\b/i.test(sql));
});
Deno.test("review rollout adds a reader capability without changing provider bindings or historical snapshots", () => {
  assertStringIncludes(sql, "accepted_identification_protocol IN (4,5,6)");
  assertStringIncludes(
    sql,
    "CREATE TRIGGER clear_deleted_job_ai_identification_review",
  );
  assertStringIncludes(
    sql,
    "CREATE TRIGGER sync_community_identification_review",
  );
  assert(
    !/\b(?:INSERT INTO|UPDATE|DELETE FROM)\s+internal\.(?:identification_provider_bindings|ai_quota_policies|export_job_source_rows)\b/i
      .test(sql),
  );
});
