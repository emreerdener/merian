import {
  assertEquals,
  assertMatch,
  assertNotMatch,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

Deno.test("Explore identity DB - default public username is tag-ready and deterministic", async () => {
  await withExploreDbTest("exploreIdentityDb.test", async (client: Client) => {
    const userId = "00000000-0000-0000-0000-00000000b7ea";

    const firstResult = await client.queryObject<{ username: string }>(
      `
        SELECT public.build_default_public_username($1::uuid) AS username
      `,
      [userId],
    );

    const secondResult = await client.queryObject<{ username: string }>(
      `
        SELECT public.build_default_public_username($1::uuid) AS username
      `,
      [userId],
    );

    const username = firstResult.rows[0]?.username ?? "";

    assertEquals(username, secondResult.rows[0]?.username ?? "");
    assertMatch(username, /^[a-z][a-z0-9_]{1,22}[a-z0-9]$/);
    assertNotMatch(username, /[A-Z\s]/);
    assertNotMatch(username, /^explorer_[a-f0-9]{6}$/);
  });
});

Deno.test("Explore identity DB - public username normalization and validation", async () => {
  await withExploreDbTest("exploreIdentityDb.test", async (client: Client) => {
    const result = await client.queryObject<{
      normalized: string;
      valid_normalized: boolean;
      reserved_valid: boolean;
      repeated_underscore_valid: boolean;
    }>(
      `
        SELECT
          public.normalize_public_username('@Stone Glen 72') AS normalized,
          public.is_valid_public_username(public.normalize_public_username('@Stone Glen 72')) AS valid_normalized,
          public.is_valid_public_username('admin') AS reserved_valid,
          public.is_valid_public_username('stone__glen') AS repeated_underscore_valid
      `,
    );

    const row = result.rows[0];
    assertEquals(row?.normalized, "stone_glen_72");
    assertEquals(row?.valid_normalized, true);
    assertEquals(row?.reserved_valid, false);
    assertEquals(row?.repeated_underscore_valid, false);
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

Deno.test("Explore identity DB - custom avatar wins over provider refresh", async () => {
  await withExploreDbTest("exploreIdentityDb.test", async (client: Client) => {
    const userId = "00000000-0000-0000-0000-00000000b8ea";
    const providerAvatar = "https://accounts.google.com/avatar.jpg";
    const customAvatar =
      "https://media.merian.app/avatars/00000000-0000-0000-0000-00000000b8ea/avatar.webp";

    await insertUser(client, userId, "Avatar User", providerAvatar);
    await client.queryArray(
      `
        UPDATE public.users
        SET custom_avatar_url = $2,
            custom_avatar_updated_at = now()
        WHERE id = $1
      `,
      [userId, customAvatar],
    );

    await client.queryArray(
      "SELECT public.refresh_public_author_identity($1::uuid)",
      [userId],
    );

    const result = await client.queryObject<{ public_avatar_url: string }>(
      `
        SELECT public_avatar_url
        FROM public.users
        WHERE id = $1
      `,
      [userId],
    );

    assertEquals(result.rows[0]?.public_avatar_url, customAvatar);
  });
});

Deno.test("Explore identity DB - repair function aligns Explore post owner with scan owner", async () => {
  await withExploreDbTest("exploreIdentityDb.test", async (client: Client) => {
    const ghostId = "00000000-0000-0000-0000-00000000a001";
    const targetId = "00000000-0000-0000-0000-00000000a002";
    const speciesId = "00000000-0000-0000-0000-00000000a003";
    const scanId = "00000000-0000-0000-0000-00000000a004";
    const postId = "00000000-0000-0000-0000-00000000a005";

    await insertUser(client, ghostId, "Ghost Alias");
    await insertUser(client, targetId, "Logged In User");
    await insertSpecies(client, speciesId, "Rosa testus");
    await insertScan(client, {
      id: scanId,
      userId: targetId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
    });
    await insertExplorePost(client, {
      id: postId,
      userId: ghostId,
      scanId,
    });

    const repairResult = await client.queryObject<{ repaired_count: number }>(
      `
        SELECT public.repair_explore_post_ownership_for_user($1::uuid) AS repaired_count
      `,
      [targetId],
    );

    assertEquals(repairResult.rows[0]?.repaired_count, 1);

    const postResult = await client.queryObject<{ user_id: string }>(
      `
        SELECT user_id::text
        FROM public.explore_posts
        WHERE id = $1
      `,
      [postId],
    );

    assertEquals(postResult.rows[0]?.user_id, targetId);
  });
});
