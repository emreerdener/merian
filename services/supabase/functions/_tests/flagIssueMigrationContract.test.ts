import { assert, assertStringIncludes } from "@std/assert";

const initialMigrationUrl = new URL(
  "../../migrations/20260831120000_submit_owned_flag_issue_atomically.sql",
  import.meta.url,
);
const repairMigrationUrl = new URL(
  "../../migrations/20260901032158_repair_owned_flag_issue_insert_detection.sql",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/--.*$/gm, "").replaceAll(/\s+/g, " ").trim();
}

Deno.test("owned flag issue is atomic, lock-ordered, and service-only", async () => {
  const initialSql = compact(await Deno.readTextFile(initialMigrationUrl));
  const sql = compact(await Deno.readTextFile(repairMigrationUrl));

  assertStringIncludes(
    initialSql,
    "CREATE OR REPLACE FUNCTION public.submit_owned_flag_issue( p_scan_id UUID, p_reporter_user_id UUID, p_flag_reason TEXT, p_user_suggestion TEXT )",
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.submit_owned_flag_issue( p_scan_id UUID, p_reporter_user_id UUID, p_flag_reason TEXT, p_user_suggestion TEXT )",
      "SECURITY INVOKER SET search_path = ''",
      "INSERT INTO public.flagged_reviews",
      "FROM public.scans AS scan WHERE scan.id = p_scan_id AND scan.user_id = p_reporter_user_id AND scan.is_tombstoned IS FALSE; GET DIAGNOSTICS inserted_review_count = ROW_COUNT",
      "IF inserted_review_count = 0 THEN",
      "IF NOT FOUND OR scan_is_tombstoned THEN RETURN 'not_found'",
      "RETURN 'not_owner'",
      "FROM public.scans AS scan WHERE scan.id = p_scan_id FOR UPDATE OF scan",
      "OR scan_owner_id IS DISTINCT FROM p_reporter_user_id THEN RAISE EXCEPTION 'flag_issue_ownership_changed'",
      "UPDATE public.scans AS scan SET is_flagged = TRUE",
      "RETURN 'submitted'",
      "REVOKE ALL ON FUNCTION public.submit_owned_flag_issue( UUID, UUID, TEXT, TEXT ) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.submit_owned_flag_issue( UUID, UUID, TEXT, TEXT ) TO service_role",
      "GRANT INSERT ON TABLE public.flagged_reviews TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const reviewInsert = sql.indexOf("INSERT INTO public.flagged_reviews");
  const ownerPredicate = sql.indexOf(
    "AND scan.user_id = p_reporter_user_id",
    reviewInsert,
  );
  const insertedCount = sql.indexOf(
    "GET DIAGNOSTICS inserted_review_count = ROW_COUNT",
    ownerPredicate,
  );
  const scanLock = sql.indexOf("FOR UPDATE OF scan", insertedCount);
  const scanUpdate = sql.indexOf("UPDATE public.scans AS scan");
  assert(
    reviewInsert >= 0 && ownerPredicate > reviewInsert &&
      insertedCount > ownerPredicate && scanLock > insertedCount &&
      scanUpdate > scanLock,
    "The transaction must conditionally insert by owner, let the review trigger run, then lock and update the scan.",
  );
  assert(
    !sql.includes("RETURNING id INTO flagged_review_id") &&
      !sql.includes("GRANT SELECT"),
    "The invoker must detect the conditional insert without flagged-review read access.",
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.submit_owned_flag_issue( UUID, UUID, TEXT, TEXT ) TO authenticated",
    ),
    "Authenticated clients must not call the service orchestration RPC directly.",
  );
});
