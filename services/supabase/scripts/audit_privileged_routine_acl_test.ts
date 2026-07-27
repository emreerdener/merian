import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import {
  buildAuditReport,
  type CatalogSnapshot,
  parseMode,
  type RoutineCatalogRow,
} from "./audit_privileged_routine_acl.ts";

function routine(
  overrides: Partial<RoutineCatalogRow> = {},
): RoutineCatalogRow {
  return {
    signature: "public.reviewed(uuid)",
    owner: "postgres",
    language: "plpgsql",
    proacl: "{postgres=X/postgres}",
    proconfig: ['search_path=""'],
    public_can_execute: false,
    anon_can_execute: false,
    authenticated_can_execute: true,
    service_role_can_execute: false,
    has_empty_search_path: true,
    has_authenticated_caller_check: true,
    has_service_role_caller_check: false,
    has_jwt_only_service_role_dispatch: false,
    ...overrides,
  };
}

function snapshot(
  overrides: Partial<CatalogSnapshot> = {},
): CatalogSnapshot {
  return {
    current_user: "postgres",
    allowlist_table_exists: true,
    routines: [routine()],
    allowlist: [{
      role_name: "authenticated",
      routine_signature: "public.reviewed(uuid)",
      purpose: "Caller-bound account operation.",
    }],
    unsafe_default_privileges: [],
    public_schema_creators: [],
    allowlist_table_readers: [
      { role_name: "anon", can_select: false },
      { role_name: "authenticated", can_select: false },
      { role_name: "service_role", can_select: false },
    ],
    ...overrides,
  };
}

Deno.test("clean privileged-routine catalog passes enforcement", () => {
  const report = buildAuditReport(snapshot(), "enforce");

  assert(report.passed);
  assertEquals(report.summary.violation_count, 0);
  assertEquals(report.summary.reviewed_authenticated_grants, 1);
});

Deno.test("catalog audit reports every privilege boundary failure", () => {
  const unsafeRoutine = routine({
    owner: "supabase_admin",
    public_can_execute: true,
    anon_can_execute: true,
    authenticated_can_execute: false,
    service_role_can_execute: true,
    has_empty_search_path: false,
    has_authenticated_caller_check: false,
    has_jwt_only_service_role_dispatch: true,
  });
  const report = buildAuditReport(
    snapshot({
      allowlist_table_exists: false,
      routines: [unsafeRoutine],
      allowlist: [{
        role_name: "authenticated",
        routine_signature: "public.reviewed(uuid)",
        purpose: "Expected grant.",
      }, {
        role_name: "service_role",
        routine_signature: "public.missing()",
        purpose: "Stale grant.",
      }],
      unsafe_default_privileges: [{
        creator_role: "postgres",
        privilege_scope: "global",
        grantee: "PUBLIC",
        privilege_type: "EXECUTE",
      }],
      public_schema_creators: ["authenticated"],
      allowlist_table_readers: [{
        role_name: "service_role",
        can_select: true,
      }],
    }),
    "enforce",
  );

  assert(!report.passed);
  assert(report.violations.missing_allowlist_table);
  assertEquals(report.violations.public_execute, ["public.reviewed(uuid)"]);
  assertEquals(report.violations.anon_execute, ["public.reviewed(uuid)"]);
  assertEquals(report.violations.unexpected_service_role_execute, [
    "public.reviewed(uuid)",
  ]);
  assertEquals(report.violations.unsafe_search_path, [
    "public.reviewed(uuid)",
  ]);
  assertEquals(report.violations.missing_authenticated_caller_checks, [
    "public.reviewed(uuid)",
  ]);
  assertEquals(report.violations.jwt_only_service_role_dispatch, [
    "public.reviewed(uuid)",
  ]);
  assertEquals(report.violations.stale_or_missing_allowlist_grants, [
    "authenticated:public.reviewed(uuid)",
    "service_role:public.missing()",
  ]);
  assertEquals(report.violations.unexpected_routine_owners, [
    "supabase_admin:public.reviewed(uuid)",
  ]);
  assertEquals(report.violations.unsafe_default_privileges, [
    "postgres:global:PUBLIC:EXECUTE",
  ]);
  assertEquals(report.violations.public_schema_creators, ["authenticated"]);
  assertEquals(report.violations.allowlist_table_readers, ["service_role"]);
});

Deno.test("catalog audit mode parser is fail-closed", () => {
  assertEquals(parseMode(["--report"]), "report");
  assertEquals(parseMode(["--enforce"]), "enforce");
  assertThrows(() => parseMode([]));
  assertThrows(() => parseMode(["--report", "--enforce"]));
  assertThrows(() => parseMode(["--unknown"]));
});
