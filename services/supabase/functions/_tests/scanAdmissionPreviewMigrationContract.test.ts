import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260809155517_add_scan_admission_preview.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("scan admission preview is caller-scoped and read-only", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.get_my_scan_admission_preview( p_flash_fallback_eligible BOOLEAN )",
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s'",
      "caller_id UUID := (SELECT auth.uid())",
      "FROM internal.resolve_effective_entitlement(caller_id) AS entitlement",
      "FROM internal.ai_quota_counters AS counters",
      "counters.scope_key = caller_id::TEXT",
      "'daily_quota_exhausted'::TEXT",
      "REVOKE ALL ON FUNCTION public.get_my_scan_admission_preview(BOOLEAN) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.get_my_scan_admission_preview(BOOLEAN) TO authenticated",
      "'public.get_my_scan_admission_preview(boolean)'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("INSERT INTO internal.ai_quota_counters") &&
      !sql.includes("UPDATE internal.ai_quota_counters") &&
      !sql.includes("DELETE FROM internal.ai_quota_counters"),
    "preview must never reserve or mutate provider quota",
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.get_my_scan_admission_preview(BOOLEAN) TO anon",
    ) &&
      !sql.includes(
        "GRANT EXECUTE ON FUNCTION public.get_my_scan_admission_preview(BOOLEAN) TO service_role",
      ),
    "preview must remain an authenticated caller-only RPC",
  );
});
