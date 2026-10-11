import { assert, assertEquals } from "@std/assert";
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011164435_extract_initial_assignment_entitlement_projection.sql",
    import.meta.url,
  ),
);
Deno.test("fresh entitlement projection is private and cannot fund or grant", () => {
  const helper = migration.split(
    "CREATE FUNCTION internal.resolve_fresh_quota_entitlement",
  )[1].split("$function$;")[0];
  assert(
    !/\b(?:INSERT|UPDATE internal|DELETE|set_config|reserve_ai_quota|commit_identification|net\.http)\b/i
      .test(helper),
  );
  assert(helper.includes("SECURITY INVOKER SET search_path = ''"));
  assert(migration.includes("FROM PUBLIC, anon, authenticated, service_role"));
  assertEquals([...migration.matchAll(/CREATE FUNCTION public\./g)].length, 0);
  assert(
    !/UPDATE internal\.initial_analysis_rollout|cron\.schedule/i.test(
      migration,
    ),
  );
});
Deno.test("extraction preserves the existing replay and outer namespace owners", () => {
  const old = migration.split("old_fragment := $old$")[1].split("$old$;")[0];
  assert(old.startsWith("        IF app_user.subscription_tier ="));
  assert(
    !/active_reservation|initial_analysis_operation_fences|pg_advisory|require_service_role/
      .test(old),
  );
  assert(migration.includes("initial entitlement projection source drift"));
  assert(migration.includes("/ pg_catalog.length(old_fragment) <> 1"));
  assert(migration.includes("FOR UPDATE"));
  assert(migration.includes("FOR SHARE"));
});
