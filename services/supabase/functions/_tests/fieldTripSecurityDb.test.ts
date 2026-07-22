import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { withExploreDbTest } from "./exploreDbTestHelpers.ts";

Deno.test("Field Trip SECURITY DEFINER functions are service-role only", async () => {
  await withExploreDbTest(
    "fieldTripSecurityDb.test",
    async (client: Client) => {
      const result = await client.queryObject<{
        signature: string;
        anon_can_execute: boolean;
        authenticated_can_execute: boolean;
        service_role_can_execute: boolean;
      }>(
        `
          SELECT
            procedure.oid::REGPROCEDURE::TEXT AS signature,
            HAS_FUNCTION_PRIVILEGE('anon', procedure.oid, 'EXECUTE') AS anon_can_execute,
            HAS_FUNCTION_PRIVILEGE('authenticated', procedure.oid, 'EXECUTE') AS authenticated_can_execute,
            HAS_FUNCTION_PRIVILEGE('service_role', procedure.oid, 'EXECUTE') AS service_role_can_execute
          FROM pg_proc procedure
          JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
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
        result.rows.filter((row) => !row.service_role_can_execute).map((row) =>
          row.signature
        ),
        [],
      );
    },
  );
});
