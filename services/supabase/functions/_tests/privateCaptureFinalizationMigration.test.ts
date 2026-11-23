import { assert } from "@std/assert";

Deno.test("private finalization claims only schedule accepted immutable evidence", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261121003715_claim_private_capture_finalization.sql",
      import.meta.url,
    ),
  );
  for (
    const contract of [
      "internal.require_service_role()",
      "FOR UPDATE SKIP LOCKED",
      "pg_try_advisory_xact_lock",
      "public.recover_owned_initial_result(saved.owner_id,request)",
      "private_capture_request_sha256 IS NOT NULL AND accepted_result IS NOT NULL",
      "internal.account_deletion_jobs",
      "internal.scan_deletion_tombstones",
      "internal.capture_source_admission_stops",
      "witness.recovery#>'{intent,request_payload}'",
      "ON DELETE CASCADE",
      "ENABLE ROW LEVEL SECURITY",
      "interval '5 minutes'",
      "p_limit NOT BETWEEN 1 AND 5",
      "internal.privileged_routine_grants",
    ]
  ) assert(sql.includes(contract), contract);
  const body = sql.split("AS $$")[1].split("$$;")[0].replace(/--[^\n]*/g, "");
  assert(
    !/\b(?:UPDATE|INSERT INTO|DELETE FROM)\s+(?:public\.|internal\.ordinary_initial_evidence|internal\.complimentary_scan_usage)/i
      .test(body),
  );
  assert(!sql.includes("failed_terminal"));
});

Deno.test("finalization fences the actual scan insert and completion against account retirement", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261121004841_fence_scan_insertion_against_account_retirement.sql",
      import.meta.url,
    ),
  );
  for (
    const invariant of [
      "BEFORE INSERT ON public.scans",
      "NEW.user_id IS NOT NULL",
      "pg_try_advisory_xact_lock",
      "merian-capture-account-retirement:",
      "internal.account_deletion_jobs",
      "internal.private_capture_finalization_ready(uuid,uuid)",
      "FROM PUBLIC,anon,authenticated,service_role",
      "SET search_path=''",
    ]
  ) {
    assert(sql.includes(invariant), invariant);
  }
  assert(!sql.includes("GRANT EXECUTE"));
});
