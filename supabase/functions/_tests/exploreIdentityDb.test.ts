import {
  assertEquals,
  assertMatch,
  assertNotMatch,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { withExploreDbTest } from "./exploreDbTestHelpers.ts";

Deno.test("Explore identity DB - default public alias is human-readable and deterministic", async () => {
  await withExploreDbTest("exploreIdentityDb.test", async (client: Client) => {
    const userId = "00000000-0000-0000-0000-00000000b7ea";

    const firstResult = await client.queryObject<{ alias: string }>(
      `
        SELECT public.build_default_public_alias($1::uuid) AS alias
      `,
      [userId],
    );

    const secondResult = await client.queryObject<{ alias: string }>(
      `
        SELECT public.build_default_public_alias($1::uuid) AS alias
      `,
      [userId],
    );

    const alias = firstResult.rows[0]?.alias ?? "";

    assertEquals(alias, secondResult.rows[0]?.alias ?? "");
    assertMatch(alias, /^[A-Z][a-z]+ [A-Z][a-z]+ [1-9][0-9]$/);
    assertNotMatch(alias, /^Explorer [A-F0-9]{6}$/);
  });
});

Deno.test("Explore identity DB - auth user updates refresh public author identity", async () => {
  await withExploreDbTest("exploreIdentityDb.test", async (client: Client) => {
    const result = await client.queryObject<{ trigger_count: number }>(
      `
        SELECT COUNT(*)::int AS trigger_count
        FROM pg_trigger
        WHERE tgname = 'on_auth_user_updated'
          AND tgrelid = 'auth.users'::regclass
          AND NOT tgisinternal
      `,
    );

    assertEquals(result.rows[0]?.trigger_count, 1);
  });
});
