import { assert, assertEquals } from "@std/assert";
import { MEDIA_BUDGETS } from "../_shared/mediaBudgets.ts";

Deno.test("retained destination recovery cannot reopen uploads or depend on mutable ledger rows", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261120141905_retain_capture_destination_verification.sql",
      import.meta.url,
    ),
  );
  const recovery =
    sql.split("CREATE FUNCTION internal.lock_capture_promotion_recovery")[1]
      .split("CREATE FUNCTION public.authorize_capture_promotion_recovery")[0];
  assert(recovery.includes("saved.write_authorized_at IS NULL"));
  assert(recovery.includes("saved.retired_at IS NOT NULL"));
  assert(recovery.includes("saved.cohort_id IS NULL"));
  assert(
    recovery.includes(
      "internal.capture_promotion_binding(saved) IS DISTINCT FROM p_binding",
    ),
  );
  assert(recovery.includes("member->'binding'=p_binding)=1"));
  assert(
    !/scan_media_assets|scan_ingestion_jobs|scan_ingestion_intents|capture_object_authorities/
      .test(recovery),
  );
  const receipt =
    sql.split("CREATE FUNCTION public.record_capture_promotion_verification")[1]
      .split("REVOKE ALL ON FUNCTION")[0];
  assert(receipt.includes("IF saved.destination_verified_at IS NULL THEN"));
  assert(
    receipt.includes("internal.lock_capture_promotion_recovery(p_binding)"),
  );
  assertEquals((receipt.match(/UPDATE /g) ?? []).length, 1);
  assert(
    !/DELETE FROM|write_authorized_at\s*=|retired_at\s*=|bound_at|cron\.schedule|initial_evidence_generation/i
      .test(sql),
  );
  assert(
    sql.includes(
      `pg_catalog.jsonb_array_length(p_bindings) NOT BETWEEN 1 AND ${MEDIA_BUDGETS.maxStagingFiles}`,
    ),
  );
  assert(
    sql.includes(
      "seal := public.register_capture_promotion_cohort(p_cohort,job,p_manifest,p_request,p_bindings)",
    ),
  );
  assert(!/GRANT\s+SELECT/i.test(sql));
});
