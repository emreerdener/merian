/**
 * Read-only catalog audit for public SECURITY DEFINER routines.
 *
 * Required env:
 *   MERIAN_DATABASE_URL
 *
 * Modes:
 *   --report   Print the current pg_proc/default-ACL snapshot and always exit 0.
 *   --enforce  Print the snapshot and exit non-zero when an invariant fails.
 *
 * The database URL is never included in output.
 */

import postgres, { type Sql } from "npm:postgres@3.4.7";

export type AuditMode = "report" | "enforce";
export type ApiRole = "authenticated" | "service_role";

export interface RoutineCatalogRow {
  signature: string;
  owner: string;
  language: string;
  proacl: string | null;
  proconfig: string[] | null;
  public_can_execute: boolean;
  anon_can_execute: boolean;
  authenticated_can_execute: boolean;
  service_role_can_execute: boolean;
  has_empty_search_path: boolean;
  has_authenticated_caller_check: boolean;
  has_service_role_caller_check: boolean;
}

export interface RoutineGrantRow {
  role_name: ApiRole;
  routine_signature: string;
  purpose: string;
}

export interface DefaultPrivilegeGrantRow {
  creator_role: string;
  privilege_scope: "global" | "public";
  grantee: string;
  privilege_type: string;
}

export interface AllowlistTableGrantRow {
  role_name: string;
  can_select: boolean;
}

export interface CatalogSnapshot {
  current_user: string;
  allowlist_table_exists: boolean;
  routines: RoutineCatalogRow[];
  allowlist: RoutineGrantRow[];
  unsafe_default_privileges: DefaultPrivilegeGrantRow[];
  public_schema_creators: string[];
  allowlist_table_readers: AllowlistTableGrantRow[];
}

export interface AuditViolations {
  missing_allowlist_table: boolean;
  unexpected_routine_owners: string[];
  public_execute: string[];
  anon_execute: string[];
  unexpected_authenticated_execute: string[];
  unexpected_service_role_execute: string[];
  stale_or_missing_allowlist_grants: string[];
  unsafe_search_path: string[];
  missing_authenticated_caller_checks: string[];
  missing_service_role_caller_checks: string[];
  unsafe_default_privileges: string[];
  public_schema_creators: string[];
  allowlist_table_readers: string[];
}

export interface AuditReport {
  mode: AuditMode;
  passed: boolean;
  summary: {
    definer_routine_count: number;
    reviewed_authenticated_grants: number;
    reviewed_service_role_grants: number;
    violation_count: number;
  };
  violations: AuditViolations;
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
    console.error(`Privileged routine catalog audit failed: ${safeMessage}`);
    Deno.exit(2);
  }
}

export function parseMode(args: string[]): AuditMode {
  if (args.length !== 1 || !["--report", "--enforce"].includes(args[0])) {
    throw new Error(
      "Usage: audit_privileged_routine_acl.ts --report|--enforce",
    );
  }
  return args[0] === "--report" ? "report" : "enforce";
}

export function buildAuditReport(
  snapshot: CatalogSnapshot,
  mode: AuditMode,
): AuditReport {
  const routineBySignature = new Map(
    snapshot.routines.map((routine) => [routine.signature, routine]),
  );
  const allowlistKeys = new Set(
    snapshot.allowlist.map((grant) =>
      allowlistKey(grant.role_name, grant.routine_signature)
    ),
  );

  const unexpectedAuthenticated = snapshot.routines
    .filter((routine) =>
      routine.authenticated_can_execute &&
      !allowlistKeys.has(allowlistKey("authenticated", routine.signature))
    )
    .map((routine) => routine.signature);
  const unexpectedServiceRole = snapshot.routines
    .filter((routine) =>
      routine.service_role_can_execute &&
      !allowlistKeys.has(allowlistKey("service_role", routine.signature))
    )
    .map((routine) => routine.signature);
  const staleOrMissing = snapshot.allowlist
    .filter((grant) => {
      const routine = routineBySignature.get(grant.routine_signature);
      if (!routine) return true;
      return grant.role_name === "authenticated"
        ? !routine.authenticated_can_execute
        : !routine.service_role_can_execute;
    })
    .map((grant) => `${grant.role_name}:${grant.routine_signature}`);

  const violations: AuditViolations = {
    missing_allowlist_table: !snapshot.allowlist_table_exists,
    unexpected_routine_owners: snapshot.routines
      .filter((routine) => routine.owner !== "postgres")
      .map((routine) => `${routine.owner}:${routine.signature}`),
    public_execute: snapshot.routines
      .filter((routine) => routine.public_can_execute)
      .map((routine) => routine.signature),
    anon_execute: snapshot.routines
      .filter((routine) => routine.anon_can_execute)
      .map((routine) => routine.signature),
    unexpected_authenticated_execute: unexpectedAuthenticated,
    unexpected_service_role_execute: unexpectedServiceRole,
    stale_or_missing_allowlist_grants: staleOrMissing,
    unsafe_search_path: snapshot.routines
      .filter((routine) => !routine.has_empty_search_path)
      .map((routine) => routine.signature),
    missing_authenticated_caller_checks: snapshot.allowlist
      .filter((grant) => grant.role_name === "authenticated")
      .filter((grant) =>
        !routineBySignature.get(grant.routine_signature)
          ?.has_authenticated_caller_check
      )
      .map((grant) => grant.routine_signature),
    missing_service_role_caller_checks: snapshot.allowlist
      .filter((grant) => grant.role_name === "service_role")
      .filter((grant) =>
        !routineBySignature.get(grant.routine_signature)
          ?.has_service_role_caller_check
      )
      .map((grant) => grant.routine_signature),
    unsafe_default_privileges: snapshot.unsafe_default_privileges.map(
      (grant) =>
        `${grant.creator_role}:${grant.privilege_scope}:${grant.grantee}:${grant.privilege_type}`,
    ),
    public_schema_creators: [...snapshot.public_schema_creators],
    allowlist_table_readers: snapshot.allowlist_table_readers
      .filter((grant) => grant.can_select)
      .map((grant) => grant.role_name),
  };

  const violationCount = countViolations(violations);
  return {
    mode,
    passed: violationCount === 0,
    summary: {
      definer_routine_count: snapshot.routines.length,
      reviewed_authenticated_grants:
        snapshot.allowlist.filter((grant) =>
          grant.role_name === "authenticated"
        ).length,
      reviewed_service_role_grants:
        snapshot.allowlist.filter((grant) => grant.role_name === "service_role")
          .length,
      violation_count: violationCount,
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

    const currentUserRows = await queryRows<{ current_user: string }>(
      sql,
      "SELECT CURRENT_USER::TEXT AS current_user",
    );
    const allowlistExistsRows = await queryRows<{
      allowlist_table_exists: boolean;
    }>(
      sql,
      `
        SELECT pg_catalog.TO_REGCLASS(
          'internal.privileged_routine_grants'
        ) IS NOT NULL AS allowlist_table_exists
      `,
    );
    const allowlistTableExists = allowlistExistsRows[0].allowlist_table_exists;

    const routines = await queryRows<RoutineCatalogRow>(
      sql,
      `
        SELECT
          function_row.oid::REGPROCEDURE::TEXT AS signature,
          owner_row.rolname AS owner,
          language_row.lanname AS language,
          function_row.proacl::TEXT AS proacl,
          function_row.proconfig,
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
          ) AS public_can_execute,
          pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'anon',
            function_row.oid,
            'EXECUTE'
          ) AS anon_can_execute,
          pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'authenticated',
            function_row.oid,
            'EXECUTE'
          ) AS authenticated_can_execute,
          pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'service_role',
            function_row.oid,
            'EXECUTE'
          ) AS service_role_can_execute,
          COALESCE(function_row.proconfig, ARRAY[]::TEXT[])
            @> ARRAY['search_path=""']::TEXT[]
            AS has_empty_search_path,
          (
            function_row.prosrc ~ 'internal[.]require_admin[(]'
            OR function_row.prosrc ~ 'auth[.](uid|jwt)[(]'
          ) AS has_authenticated_caller_check,
          function_row.prosrc LIKE
            '%internal.require_service_role()%'
            AS has_service_role_caller_check
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        JOIN pg_catalog.pg_roles AS owner_row
          ON owner_row.oid = function_row.proowner
        JOIN pg_catalog.pg_language AS language_row
          ON language_row.oid = function_row.prolang
        WHERE namespace_row.nspname = 'public'
          AND function_row.prosecdef
        ORDER BY signature
      `,
    );

    let allowlist: RoutineGrantRow[] = [];
    let allowlistTableReaders: AllowlistTableGrantRow[] = [];
    if (allowlistTableExists) {
      allowlist = await queryRows<RoutineGrantRow>(
        sql,
        `
          SELECT role_name, routine_signature, purpose
          FROM internal.privileged_routine_grants
          ORDER BY role_name, routine_signature
        `,
      );

      allowlistTableReaders = await queryRows<
        AllowlistTableGrantRow
      >(
        sql,
        `
          SELECT
            api_role.role_name,
            pg_catalog.HAS_TABLE_PRIVILEGE(
              api_role.role_name,
              'internal.privileged_routine_grants',
              'SELECT'
            ) AS can_select
          FROM (
            VALUES ('anon'), ('authenticated'), ('service_role')
          ) AS api_role(role_name)
          ORDER BY api_role.role_name
        `,
      );
    }

    const unsafeDefaultPrivileges = await queryRows<
      DefaultPrivilegeGrantRow
    >(
      sql,
      `
        WITH creator_roles AS (
          SELECT DISTINCT owner_row.oid, owner_row.rolname
          FROM pg_catalog.pg_proc AS function_row
          JOIN pg_catalog.pg_namespace AS namespace_row
            ON namespace_row.oid = function_row.pronamespace
          JOIN pg_catalog.pg_roles AS owner_row
            ON owner_row.oid = function_row.proowner
          WHERE namespace_row.nspname = 'public'
            AND function_row.prosecdef

          UNION

          SELECT role_row.oid, role_row.rolname
          FROM pg_catalog.pg_roles AS role_row
          WHERE role_row.rolname = 'postgres'
        ),
        candidate_defaults AS (
          SELECT
            creator.rolname AS creator_role,
            'global'::TEXT AS privilege_scope,
            COALESCE(
              default_acl.defaclacl,
              pg_catalog.ACLDEFAULT('f', creator.oid)
            ) AS privilege_acl
          FROM creator_roles AS creator
          LEFT JOIN pg_catalog.pg_default_acl AS default_acl
            ON default_acl.defaclrole = creator.oid
           AND default_acl.defaclnamespace = 0
           AND default_acl.defaclobjtype = 'f'

          UNION ALL

          SELECT
            creator.rolname AS creator_role,
            'public'::TEXT AS privilege_scope,
            default_acl.defaclacl AS privilege_acl
          FROM creator_roles AS creator
          JOIN pg_catalog.pg_default_acl AS default_acl
            ON default_acl.defaclrole = creator.oid
           AND default_acl.defaclnamespace = (
             SELECT namespace_row.oid
             FROM pg_catalog.pg_namespace AS namespace_row
             WHERE namespace_row.nspname = 'public'
           )
           AND default_acl.defaclobjtype = 'f'
        )
        SELECT
          candidate.creator_role,
          candidate.privilege_scope,
          CASE
            WHEN acl_row.grantee = 0 THEN 'PUBLIC'
            ELSE pg_catalog.PG_GET_USERBYID(acl_row.grantee)
          END AS grantee,
          acl_row.privilege_type
        FROM candidate_defaults AS candidate
        CROSS JOIN LATERAL pg_catalog.ACLEXPLODE(
          candidate.privilege_acl
        ) AS acl_row
        WHERE acl_row.privilege_type = 'EXECUTE'
          AND (
            acl_row.grantee = 0
            OR acl_row.grantee IN (
              SELECT role_row.oid
              FROM pg_catalog.pg_roles AS role_row
              WHERE role_row.rolname IN (
                'anon',
                'authenticated',
                'service_role'
              )
            )
          )
        ORDER BY
          candidate.creator_role,
          candidate.privilege_scope,
          grantee
      `,
    );

    const schemaCreatorRows = await queryRows<{
      role_name: string;
    }>(
      sql,
      `
        SELECT api_role.role_name
        FROM (
          VALUES ('anon'), ('authenticated'), ('service_role')
        ) AS api_role(role_name)
        WHERE pg_catalog.HAS_SCHEMA_PRIVILEGE(
          api_role.role_name,
          'public',
          'CREATE'
        )
        ORDER BY api_role.role_name
      `,
    );

    await sql.unsafe("ROLLBACK");
    return {
      current_user: currentUserRows[0].current_user,
      allowlist_table_exists: allowlistTableExists,
      routines,
      allowlist,
      unsafe_default_privileges: unsafeDefaultPrivileges,
      public_schema_creators: schemaCreatorRows.map((row) => row.role_name),
      allowlist_table_readers: allowlistTableReaders,
    };
  } catch (error) {
    try {
      await sql.unsafe("ROLLBACK");
    } catch {
      // The original catalog-query error is more useful.
    }
    throw error;
  } finally {
    await sql.end();
  }
}

async function queryRows<T extends object>(
  sql: Sql,
  query: string,
): Promise<T[]> {
  return await sql.unsafe(query) as unknown as T[];
}

function allowlistKey(role: ApiRole, signature: string): string {
  return `${role}:${signature}`;
}

function countViolations(violations: AuditViolations): number {
  return Object.values(violations).reduce((count, value) => {
    if (typeof value === "boolean") return count + Number(value);
    return count + value.length;
  }, 0);
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required environment variable ${name}.`);
  return value;
}
