import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  type AuditMode,
  buildAuditReport,
  type CatalogSnapshot,
  expectedSourceRelations,
  parseMode,
  type RoutineCatalogRow,
} from "./audit_field_trip_capture_context_acl.ts";

function routine(
  routineKey: RoutineCatalogRow["routine_key"],
  overrides: Partial<RoutineCatalogRow> = {},
): RoutineCatalogRow {
  const isCaptureContext = routineKey === "capture_context";
  return {
    routine_key: routineKey,
    signature: isCaptureContext
      ? "public.get_field_trip_capture_context(uuid)"
      : "internal.user_has_effective_pro(uuid)",
    object_exists: true,
    security_definer: !isCaptureContext,
    has_empty_search_path: true,
    public_can_execute: false,
    anon_can_execute: false,
    authenticated_can_execute: false,
    service_role_can_execute: true,
    definition_valid: true,
    ...overrides,
  };
}

function snapshot(overrides: Partial<CatalogSnapshot> = {}): CatalogSnapshot {
  return {
    routines: [routine("capture_context"), routine("entitlement_helper")],
    source_relations: expectedSourceRelations.map((relationName) => ({
      relation_name: relationName,
      relation_exists: true,
      service_role_can_select: true,
    })),
    ...overrides,
  };
}

Deno.test("clean Field trip capture-context ACL catalog passes", () => {
  const report = buildAuditReport(snapshot(), "enforce");

  assert(report.passed);
  assertEquals(report.violations, []);
  assertEquals(report.summary, {
    routine_count: 2,
    source_relation_count: 6,
    violation_count: 0,
  });
});

Deno.test("capture-context ACL audit reports every unsafe dependency edge", () => {
  const sourceRelations = expectedSourceRelations.map((
    relationName,
    index,
  ) => ({
    relation_name: relationName,
    relation_exists: index !== 0,
    service_role_can_select: index !== 1,
  }));
  const report = buildAuditReport(
    snapshot({
      routines: [
        routine("capture_context", {
          security_definer: true,
          has_empty_search_path: false,
          definition_valid: false,
          public_can_execute: true,
          anon_can_execute: true,
          authenticated_can_execute: true,
          service_role_can_execute: false,
        }),
        routine("entitlement_helper", {
          security_definer: false,
          has_empty_search_path: false,
          public_can_execute: true,
          anon_can_execute: true,
          authenticated_can_execute: true,
          service_role_can_execute: false,
        }),
      ],
      source_relations: sourceRelations,
    }),
    "enforce",
  );

  assert(!report.passed);
  assertEquals(report.violations, [
    "capture_context_not_security_invoker",
    "capture_context_search_path_not_empty",
    "capture_context_dependency_drift",
    "capture_context_public_execute",
    "capture_context_anon_execute",
    "capture_context_authenticated_execute",
    "capture_context_service_role_execute_missing",
    "entitlement_helper_not_security_definer",
    "entitlement_helper_search_path_not_empty",
    "entitlement_helper_public_execute",
    "entitlement_helper_anon_execute",
    "entitlement_helper_authenticated_execute",
    "entitlement_helper_service_role_execute_missing",
    "source_relation_missing:public.users",
    "source_select_missing:public.user_field_trips",
  ]);
  assertEquals(report.summary.violation_count, 15);
});

Deno.test("capture-context ACL audit fails closed on missing catalog rows", () => {
  const report = buildAuditReport(
    snapshot({ routines: [], source_relations: [] }),
    "enforce",
  );

  assert(!report.passed);
  assertEquals(report.violations, [
    "capture_context_missing",
    "entitlement_helper_missing",
    ...expectedSourceRelations.map((relationName) =>
      `source_relation_missing:${relationName}`
    ),
  ]);
});

Deno.test("capture-context ACL audit mode parser is fail-closed", () => {
  const expectedModes: Array<[string, AuditMode]> = [
    ["--report", "report"],
    ["--enforce", "enforce"],
  ];
  for (const [argument, mode] of expectedModes) {
    assertEquals(parseMode([argument]), mode);
  }
  assertThrows(() => parseMode([]));
  assertThrows(() => parseMode(["--report", "--enforce"]));
  assertThrows(() => parseMode(["--unknown"]));
});

Deno.test("capture-context production audit is catalog-only and read-only", async () => {
  const source = await Deno.readTextFile(
    new URL("./audit_field_trip_capture_context_acl.ts", import.meta.url),
  );

  assert(source.includes('sql.unsafe("BEGIN TRANSACTION READ ONLY")'));
  assert(source.includes('sql.unsafe("SET LOCAL search_path TO pg_catalog")'));
  assert(source.includes('sql.unsafe("ROLLBACK")'));
  for (const relationName of expectedSourceRelations) {
    assert(source.includes(`'${relationName}'`));
  }
});
