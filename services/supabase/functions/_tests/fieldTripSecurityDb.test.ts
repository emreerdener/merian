import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { withExploreDbTest } from "./exploreDbTestHelpers.ts";

Deno.test("Field Trip definers match the reviewed service-role allowlist", async () => {
  await withExploreDbTest(
    "fieldTripSecurityDb.test",
    async (client: Client) => {
      const result = await client.queryObject<{
        signature: string;
        service_role_allowlisted: boolean;
        anon_can_execute: boolean;
        authenticated_can_execute: boolean;
        service_role_can_execute: boolean;
        has_empty_search_path: boolean;
      }>(
        `
          SELECT
            procedure.oid::REGPROCEDURE::TEXT AS signature,
            EXISTS (
              SELECT 1
              FROM internal.privileged_routine_grants AS allowlist
              WHERE allowlist.role_name = 'service_role'
                AND pg_catalog.TO_REGPROCEDURE(
                  allowlist.routine_signature
                ) = procedure.oid
            ) AS service_role_allowlisted,
            pg_catalog.HAS_FUNCTION_PRIVILEGE(
              'anon',
              procedure.oid,
              'EXECUTE'
            ) AS anon_can_execute,
            pg_catalog.HAS_FUNCTION_PRIVILEGE(
              'authenticated',
              procedure.oid,
              'EXECUTE'
            ) AS authenticated_can_execute,
            pg_catalog.HAS_FUNCTION_PRIVILEGE(
              'service_role',
              procedure.oid,
              'EXECUTE'
            ) AS service_role_can_execute,
            COALESCE(procedure.proconfig, ARRAY[]::TEXT[])
              @> ARRAY['search_path=""']::TEXT[]
              AS has_empty_search_path
          FROM pg_catalog.pg_proc AS procedure
          JOIN pg_catalog.pg_namespace AS namespace
            ON namespace.oid = procedure.pronamespace
          WHERE namespace.nspname = 'public'
            AND procedure.prosecdef
            AND (
              procedure.proname ILIKE '%field_trip%'
              OR procedure.proname ILIKE '%challenge%'
            )
          ORDER BY signature
        `,
      );

      assert(result.rows.length >= 26);
      assertEquals(
        result.rows.filter((row) => row.anon_can_execute).map((row) =>
          row.signature
        ),
        [],
      );
      assertEquals(
        result.rows.filter((row) => row.authenticated_can_execute).map((row) =>
          row.signature
        ),
        [],
      );
      assertEquals(
        result.rows.filter((row) =>
          row.service_role_can_execute !== row.service_role_allowlisted
        ).map((row) => row.signature),
        [],
      );
      assertEquals(
        result.rows.filter((row) => !row.has_empty_search_path).map((row) =>
          row.signature
        ),
        [],
      );
    },
  );
});
