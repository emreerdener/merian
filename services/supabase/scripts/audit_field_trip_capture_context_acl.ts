/**
 * Read-only production catalog audit for the Field trip capture-context
 * SECURITY INVOKER dependency chain.
 *
 * Required env:
 *   MERIAN_DATABASE_URL
 *
 * Modes:
 *   --report   Print the aggregate catalog result and always exit 0.
 *   --enforce  Print the result and exit non-zero when an invariant fails.
 *
 * The audit reads catalog metadata only. It never reads user rows, and the
 * database URL is never included in output.
 */

import postgres, { type Sql } from "npm:postgres@3.4.7";

export type AuditMode = "report" | "enforce";
export type RoutineKey = "capture_context" | "entitlement_helper";

export const expectedSourceRelations = [
  "public.users",
  "public.user_field_trips",
  "public.field_trip_templates",
  "public.field_trip_levels",
  "public.user_field_trip_item_completions",
  "public.field_trip_checklist_items",
] as const;

export interface RoutineCatalogRow {
  routine_key: RoutineKey;
  signature: string;
  object_exists: boolean;
  security_definer: boolean;
  has_empty_search_path: boolean;
  public_can_execute: boolean;
  anon_can_execute: boolean;
  authenticated_can_execute: boolean;
  service_role_can_execute: boolean;
  definition_valid: boolean;
}

export interface SourceRelationCatalogRow {
  relation_name: string;
  relation_exists: boolean;
  service_role_can_select: boolean;
}

export interface CatalogSnapshot {
  routines: RoutineCatalogRow[];
  source_relations: SourceRelationCatalogRow[];
}

export interface AuditReport {
  mode: AuditMode;
  passed: boolean;
  summary: {
    routine_count: number;
    source_relation_count: number;
    violation_count: number;
  };
  violations: string[];
  catalog: CatalogSnapshot;
}

if (import.meta.main) {
  const mode = parseMode(Deno.args);
  const databaseUrl = requiredEnv("MERIAN_DATABASE_URL");

  try {
    const snapshot = await inspectCatalog(databaseUrl);
    const report = buildAuditReport(snapshot, mode);
    console.log(JSON.stringify(report, null, 2));
    Deno.exit(mode === "enforce" && !report.passed ? 1 : 0);
  } catch (error) {
    const rawMessage = error instanceof Error ? error.message : String(error);
    const safeMessage = rawMessage.replaceAll(databaseUrl, "[redacted]");
    console.error(
      `Field trip capture-context ACL audit failed: ${safeMessage}`,
    );
    Deno.exit(2);
  }
}

export function parseMode(args: string[]): AuditMode {
  if (args.length !== 1 || !["--report", "--enforce"].includes(args[0])) {
    throw new Error(
      "Usage: audit_field_trip_capture_context_acl.ts --report|--enforce",
    );
  }
  return args[0] === "--report" ? "report" : "enforce";
}

export function buildAuditReport(
  snapshot: CatalogSnapshot,
  mode: AuditMode,
): AuditReport {
  const violations: string[] = [];
  const routinesByKey = new Map(
    snapshot.routines.map((routine) => [routine.routine_key, routine]),
  );

  auditRoutine(
    routinesByKey.get("capture_context"),
    {
      missing: "capture_context_missing",
      securityMode: "capture_context_not_security_invoker",
      searchPath: "capture_context_search_path_not_empty",
      definition: "capture_context_dependency_drift",
      publicExecute: "capture_context_public_execute",
      anonExecute: "capture_context_anon_execute",
      authenticatedExecute: "capture_context_authenticated_execute",
      serviceExecute: "capture_context_service_role_execute_missing",
    },
    false,
    violations,
  );
  auditRoutine(
    routinesByKey.get("entitlement_helper"),
    {
      missing: "entitlement_helper_missing",
      securityMode: "entitlement_helper_not_security_definer",
      searchPath: "entitlement_helper_search_path_not_empty",
      publicExecute: "entitlement_helper_public_execute",
      anonExecute: "entitlement_helper_anon_execute",
      authenticatedExecute: "entitlement_helper_authenticated_execute",
      serviceExecute: "entitlement_helper_service_role_execute_missing",
    },
    true,
    violations,
  );

  const sourceRelationsByName = new Map(
    snapshot.source_relations.map((relation) => [
      relation.relation_name,
      relation,
    ]),
  );
  for (const relationName of expectedSourceRelations) {
    const relation = sourceRelationsByName.get(relationName);
    if (!relation?.relation_exists) {
      violations.push(`source_relation_missing:${relationName}`);
      continue;
    }
    if (!relation.service_role_can_select) {
      violations.push(`source_select_missing:${relationName}`);
    }
  }

  return {
    mode,
    passed: violations.length === 0,
    summary: {
      routine_count:
        snapshot.routines.filter((routine) => routine.object_exists).length,
      source_relation_count:
        snapshot.source_relations.filter((relation) => relation.relation_exists)
          .length,
      violation_count: violations.length,
    },
    violations,
    catalog: snapshot,
  };
}

export async function inspectCatalog(
  databaseUrl: string,
): Promise<CatalogSnapshot> {
  const sql = postgres(databaseUrl, { max: 1 });

  try {
    await sql.unsafe("BEGIN TRANSACTION READ ONLY");
    await sql.unsafe("SET LOCAL search_path TO pg_catalog");

    const routines = await queryRows<RoutineCatalogRow>(
      sql,
      `
        WITH expected_routines(routine_key, signature) AS (
          VALUES
            (
              'capture_context',
              'public.get_field_trip_capture_context(uuid)'
            ),
            (
              'entitlement_helper',
              'internal.user_has_effective_pro(uuid)'
            )
        ),
        resolved_routines AS (
          SELECT
            expected.routine_key,
            expected.signature,
            pg_catalog.TO_REGPROCEDURE(expected.signature) AS routine_oid
          FROM expected_routines AS expected
        )
        SELECT
          resolved.routine_key,
          resolved.signature,
          function_row.oid IS NOT NULL AS object_exists,
          COALESCE(function_row.prosecdef, FALSE) AS security_definer,
          COALESCE(function_row.proconfig, ARRAY[]::TEXT[])
            @> ARRAY['search_path=""']::TEXT[]
            AS has_empty_search_path,
          COALESCE(
            EXISTS (
              SELECT 1
              FROM pg_catalog.ACLEXPLODE(
                COALESCE(
                  function_row.proacl,
                  pg_catalog.ACLDEFAULT('f', function_row.proowner)
                )
              ) AS acl_row
              WHERE acl_row.grantee = 0
                AND acl_row.privilege_type = 'EXECUTE'
            ),
            FALSE
          ) AS public_can_execute,
          COALESCE(
            pg_catalog.HAS_FUNCTION_PRIVILEGE(
              'anon',
              function_row.oid,
              'EXECUTE'
            ),
            FALSE
          ) AS anon_can_execute,
          COALESCE(
            pg_catalog.HAS_FUNCTION_PRIVILEGE(
              'authenticated',
              function_row.oid,
              'EXECUTE'
            ),
            FALSE
          ) AS authenticated_can_execute,
          COALESCE(
            pg_catalog.HAS_FUNCTION_PRIVILEGE(
              'service_role',
              function_row.oid,
              'EXECUTE'
            ),
            FALSE
          ) AS service_role_can_execute,
          CASE resolved.routine_key
            WHEN 'capture_context' THEN
              pg_catalog.STRPOS(
                COALESCE(
                  pg_catalog.PG_GET_FUNCTIONDEF(function_row.oid),
                  ''
                ),
                'internal.user_has_effective_pro('
              ) > 0
              AND pg_catalog.STRPOS(
                COALESCE(
                  pg_catalog.PG_GET_FUNCTIONDEF(function_row.oid),
                  ''
                ),
                'public.users'
              ) > 0
              AND pg_catalog.STRPOS(
                COALESCE(
                  pg_catalog.PG_GET_FUNCTIONDEF(function_row.oid),
                  ''
                ),
                'public.user_field_trips'
              ) > 0
              AND pg_catalog.STRPOS(
                COALESCE(
                  pg_catalog.PG_GET_FUNCTIONDEF(function_row.oid),
                  ''
                ),
                'public.field_trip_templates'
              ) > 0
              AND pg_catalog.STRPOS(
                COALESCE(
                  pg_catalog.PG_GET_FUNCTIONDEF(function_row.oid),
                  ''
                ),
                'public.field_trip_levels'
              ) > 0
              AND pg_catalog.STRPOS(
                COALESCE(
                  pg_catalog.PG_GET_FUNCTIONDEF(function_row.oid),
                  ''
                ),
                'public.user_field_trip_item_completions'
              ) > 0
              AND pg_catalog.STRPOS(
                COALESCE(
                  pg_catalog.PG_GET_FUNCTIONDEF(function_row.oid),
                  ''
                ),
                'public.field_trip_checklist_items'
              ) > 0
            ELSE TRUE
          END AS definition_valid
        FROM resolved_routines AS resolved
        LEFT JOIN pg_catalog.pg_proc AS function_row
          ON function_row.oid = resolved.routine_oid
        ORDER BY resolved.routine_key
      `,
    );
    const sourceRelations = await queryRows<SourceRelationCatalogRow>(
      sql,
      `
        WITH expected_relations(ordinal, relation_name) AS (
          VALUES
            (1, 'public.users'),
            (2, 'public.user_field_trips'),
            (3, 'public.field_trip_templates'),
            (4, 'public.field_trip_levels'),
            (5, 'public.user_field_trip_item_completions'),
            (6, 'public.field_trip_checklist_items')
        ),
        resolved_relations AS (
          SELECT
            expected.ordinal,
            expected.relation_name,
            pg_catalog.TO_REGCLASS(expected.relation_name) AS relation_oid
          FROM expected_relations AS expected
        )
        SELECT
          resolved.relation_name,
          resolved.relation_oid IS NOT NULL AS relation_exists,
          COALESCE(
            pg_catalog.HAS_TABLE_PRIVILEGE(
              'service_role',
              resolved.relation_oid,
              'SELECT'
            ),
            FALSE
          ) AS service_role_can_select
        FROM resolved_relations AS resolved
        ORDER BY resolved.ordinal
      `,
    );

    await sql.unsafe("ROLLBACK");
    return {
      routines,
      source_relations: sourceRelations,
    };
  } catch (error) {
    try {
      await sql.unsafe("ROLLBACK");
    } catch {
      // Preserve the original catalog-query error.
    }
    throw error;
  } finally {
    await sql.end();
  }
}

interface RoutineViolationCodes {
  missing: string;
  securityMode: string;
  searchPath: string;
  definition?: string;
  publicExecute: string;
  anonExecute: string;
  authenticatedExecute: string;
  serviceExecute: string;
}

function auditRoutine(
  routine: RoutineCatalogRow | undefined,
  codes: RoutineViolationCodes,
  expectedSecurityDefiner: boolean,
  violations: string[],
): void {
  if (!routine?.object_exists) {
    violations.push(codes.missing);
    return;
  }
  if (routine.security_definer !== expectedSecurityDefiner) {
    violations.push(codes.securityMode);
  }
  if (!routine.has_empty_search_path) violations.push(codes.searchPath);
  if (codes.definition && !routine.definition_valid) {
    violations.push(codes.definition);
  }
  if (routine.public_can_execute) violations.push(codes.publicExecute);
  if (routine.anon_can_execute) violations.push(codes.anonExecute);
  if (routine.authenticated_can_execute) {
    violations.push(codes.authenticatedExecute);
  }
  if (!routine.service_role_can_execute) {
    violations.push(codes.serviceExecute);
  }
}

async function queryRows<T extends object>(
  sql: Sql,
  query: string,
): Promise<T[]> {
  return await sql.unsafe(query) as unknown as T[];
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is required.`);
  return value;
}
