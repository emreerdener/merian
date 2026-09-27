import { assert, assertStringIncludes } from "@std/assert";

Deno.test("provenance migration is additive, content-free and compatible with existing recovery", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20260926160249_persist_identification_result_provenance.sql",
      import.meta.url,
    ),
  );
  for (
    const expected of [
      "AFTER INSERT ON public.scans",
      "BEFORE UPDATE OF identification_provenance ON public.scan_ingestion_jobs",
      "jobs.scan_id = NEW.id::TEXT AND jobs.user_id = NEW.user_id",
      "identification_provenance_immutable",
      "identification_provenance_job_mismatch",
      "SECURITY DEFINER\nSET search_path = ''",
      "p_value - ARRAY[",
      "generation - ARRAY[",
      "> 2048",
    ]
  ) {
    assertStringIncludes(sql, expected);
  }
  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION public.recover_missing_owned_scan",
    ),
  );
  assert(!sql.includes("p_recovery_scan"));
  assert(!sql.includes("UPDATE internal.ai_quota_policies"));
  assert(!sql.includes("GRANT INSERT"));
  assert(!sql.includes("GRANT UPDATE"));
  assert(!sql.includes("REFERENCES internal.ai_quota_reservations"));
});
