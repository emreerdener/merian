import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { insertUser, withExploreDbTest } from "./exploreDbTestHelpers.ts";

type FollowStateRow = {
  author_user_id: string;
  follower_count: number;
  following_count: number;
  viewer_is_following: boolean;
};

async function countFollows(client: Client): Promise<number> {
  const result = await client.queryObject<{ count: bigint }>(
    "SELECT COUNT(*)::bigint AS count FROM public.user_follows",
  );
  return Number(result.rows[0]?.count ?? 0n);
}

Deno.test("User follows DB - follow and unfollow are idempotent", async () => {
  await withExploreDbTest("userFollowsDb.test", async (client: Client) => {
    const followerId = crypto.randomUUID();
    const followeeId = crypto.randomUUID();

    await insertUser(client, followerId, "Follow Idempotent Viewer");
    await insertUser(client, followeeId, "Follow Idempotent Author");

    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES ($1, $2)
        ON CONFLICT (follower_user_id, followee_user_id) DO NOTHING
      `,
      [followerId, followeeId],
    );

    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES ($1, $2)
        ON CONFLICT (follower_user_id, followee_user_id) DO NOTHING
      `,
      [followerId, followeeId],
    );

    assertEquals(await countFollows(client), 1);

    await client.queryArray(
      `
        DELETE FROM public.user_follows
        WHERE follower_user_id = $1
          AND followee_user_id = $2
      `,
      [followerId, followeeId],
    );

    await client.queryArray(
      `
        DELETE FROM public.user_follows
        WHERE follower_user_id = $1
          AND followee_user_id = $2
      `,
      [followerId, followeeId],
    );

    assertEquals(await countFollows(client), 0);
  });
});

Deno.test("User follows DB - self follow is rejected", async () => {
  await withExploreDbTest("userFollowsDb.test", async (client: Client) => {
    const userId = crypto.randomUUID();
    await insertUser(client, userId, "Self Follow Guard");

    await assertRejects(
      () =>
        client.queryArray(
          `
            INSERT INTO public.user_follows (follower_user_id, followee_user_id)
            VALUES ($1, $1)
          `,
          [userId],
        ),
      Error,
      "user_follows_no_self_follow",
    );
  });
});

Deno.test("User follows DB - blocking removes follow rows in both directions", async () => {
  await withExploreDbTest("userFollowsDb.test", async (client: Client) => {
    const blockerId = crypto.randomUUID();
    const blockedId = crypto.randomUUID();

    await insertUser(client, blockerId, "Follow Blocker");
    await insertUser(client, blockedId, "Follow Blocked");

    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES ($1, $2), ($2, $1)
      `,
      [blockerId, blockedId],
    );

    await client.queryArray(
      `
        INSERT INTO public.user_blocks (blocker_id, blocked_id)
        VALUES ($1, $2)
      `,
      [blockerId, blockedId],
    );

    assertEquals(await countFollows(client), 0);
  });
});

Deno.test("User follows DB - follow counts ignore shadowbanned users", async () => {
  await withExploreDbTest("userFollowsDb.test", async (client: Client) => {
    const viewerId = crypto.randomUUID();
    const authorId = crypto.randomUUID();
    const shadowFollowerId = crypto.randomUUID();
    const visibleFolloweeId = crypto.randomUUID();
    const shadowFolloweeId = crypto.randomUUID();

    await insertUser(client, viewerId, "Visible Viewer");
    await insertUser(client, authorId, "Counted Author");
    await insertUser(client, shadowFollowerId, "Shadow Follower");
    await insertUser(client, visibleFolloweeId, "Visible Followee");
    await insertUser(client, shadowFolloweeId, "Shadow Followee");

    await client.queryArray(
      `
        UPDATE public.users
        SET is_shadowbanned = TRUE
        WHERE id IN ($1, $2)
      `,
      [shadowFollowerId, shadowFolloweeId],
    );

    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES
          ($1, $2),
          ($3, $2),
          ($2, $4),
          ($2, $5)
      `,
      [
        viewerId,
        authorId,
        shadowFollowerId,
        visibleFolloweeId,
        shadowFolloweeId,
      ],
    );

    const state = await client.queryObject<FollowStateRow>(
      `
        SELECT *
        FROM public.get_user_follow_state($1, $2)
      `,
      [viewerId, authorId],
    );

    assertEquals(state.rows.length, 1);
    assertEquals(state.rows[0].follower_count, 1);
    assertEquals(state.rows[0].following_count, 1);
    assertEquals(state.rows[0].viewer_is_following, true);
  });
});

Deno.test("User follows DB - ghost merge reparents and dedupes conflicts", async () => {
  await withExploreDbTest("userFollowsDb.test", async (client: Client) => {
    const ghostId = crypto.randomUUID();
    const targetId = crypto.randomUUID();
    const authorId = crypto.randomUUID();
    const followerId = crypto.randomUUID();

    await insertUser(client, ghostId, "Ghost Follower");
    await insertUser(client, targetId, "Target Follower");
    await insertUser(client, authorId, "Merged Followee");
    await insertUser(client, followerId, "Existing Follower");

    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES
          ($1, $3),
          ($2, $3),
          ($4, $1),
          ($4, $2),
          ($1, $2),
          ($2, $1)
      `,
      [ghostId, targetId, authorId, followerId],
    );

    await client.queryArray(
      "SELECT public.reparent_user_follows($1, $2)",
      [ghostId, targetId],
    );

    const remaining = await client.queryObject<{
      follower_user_id: string;
      followee_user_id: string;
    }>(
      `
        SELECT follower_user_id, followee_user_id
        FROM public.user_follows
        ORDER BY follower_user_id, followee_user_id
      `,
    );

    assertEquals(remaining.rows.length, 2);
    assertEquals(
      new Set(
        remaining.rows.map((row) =>
          `${row.follower_user_id}->${row.followee_user_id}`
        ),
      ),
      new Set([
        `${followerId}->${targetId}`,
        `${targetId}->${authorId}`,
      ]),
    );
  });
});
