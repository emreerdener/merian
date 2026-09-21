import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const repairUrl = new URL(
  "../../migrations/20260921160147_fix_revenuecat_reconciliation_without_webhook_event.sql",
  import.meta.url,
);
const originalUrl = new URL(
  "../../migrations/20260812144948_introduce_stable_purchase_principals.sql",
  import.meta.url,
);

function reconciliationBody(sql: string): string {
  const start = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.apply_revenuecat_reconciliation(",
  );
  const end = sql.indexOf("$function$;", start);
  assert(start >= 0 && end > start);
  return sql.slice(start, end)
    .replaceAll(/--[^\n]*/g, "")
    .replaceAll(/\s+/g, " ").trim();
}

Deno.test("RevenueCat seed repair changes only missing-event admission, retaining lease and ordering guards", async () => {
  const [original, repair] = await Promise.all([
    Deno.readTextFile(originalUrl),
    Deno.readTextFile(repairUrl),
  ]);
  assertEquals(
    reconciliationBody(repair),
    reconciliationBody(original).replace(
      "IF legacy_state.merian_user_id IS NULL THEN",
      "IF legacy_state.last_event_id IS NULL THEN",
    ),
  );
});

Deno.test("RevenueCat seed repair retains service-only execution and bounded migration locks", async () => {
  const sql = (await Deno.readTextFile(repairUrl)).replaceAll(/\s+/g, " ");
  for (
    const fragment of [
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '30s'",
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s'",
      "PERFORM internal.require_service_role()",
      "REVOKE ALL ON FUNCTION public.apply_revenuecat_reconciliation( UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ ) FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.apply_revenuecat_reconciliation( UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ ) TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});
