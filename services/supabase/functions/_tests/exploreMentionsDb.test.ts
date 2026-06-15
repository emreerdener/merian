import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type MentionSuggestionRow = {
  user_id: string;
  username: string;
  source: "post_author" | "thread" | "following";
};

type MentionRow = {
  user_id: string;
  username: string;
};

type NotificationTypeRow = {
  user_id: string;
  type: "comment" | "comment_reply" | "comment_mention";
};

async function setUsername(
  client: Client,
  userId: string,
  username: string,
): Promise<void> {
  await client.queryArray(
    `
      UPDATE public.users
      SET public_username = $2,
          public_author_name = $2
      WHERE id = $1
    `,
    [userId, username],
  );
}

async function insertVisibleProfilePost(
  client: Client,
  userId: string,
  speciesId: string,
): Promise<string> {
  const scanId = crypto.randomUUID();
  const postId = crypto.randomUUID();

  await insertScan(client, {
    id: scanId,
    userId,
    speciesId,
    latitude: 30.2672,
    longitude: -97.7431,
    geoprivacy: "open",
  });
  await insertExplorePost(client, {
    id: postId,
    userId,
    scanId,
  });

  return postId;
}

Deno.test("Explore mentions DB - suggestions stay scoped to post, thread, and matching followed users", async () => {
  await withExploreDbTest("exploreMentionsDb.test", async (client: Client) => {
    const viewerId = crypto.randomUUID();
    const ownerId = crypto.randomUUID();
    const threadUserId = crypto.randomUUID();
    const unrelatedThreadUserId = crypto.randomUUID();
    const followedUserId = crypto.randomUUID();
    const arbitraryUserId = crypto.randomUUID();
    const parentCommentId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();

    await insertUser(client, viewerId, "Mention Viewer");
    await insertUser(client, ownerId, "Mention Owner");
    await insertUser(client, threadUserId, "Mention Thread");
    await insertUser(client, unrelatedThreadUserId, "Mention Unrelated");
    await insertUser(client, followedUserId, "Mention Followed");
    await insertUser(client, arbitraryUserId, "Mention Arbitrary");
    await setUsername(client, ownerId, "owner_mention");
    await setUsername(client, threadUserId, "thread_mention");
    await setUsername(client, unrelatedThreadUserId, "unrelated_mention");
    await setUsername(client, followedUserId, "followed_mention");
    await setUsername(client, arbitraryUserId, "arbitrary_mention");
    await insertSpecies(client, speciesId, "Rosa mentionaria");

    const targetPostId = await insertVisibleProfilePost(
      client,
      ownerId,
      speciesId,
    );
    await insertVisibleProfilePost(client, threadUserId, speciesId);
    await insertVisibleProfilePost(client, unrelatedThreadUserId, speciesId);
    await insertVisibleProfilePost(client, followedUserId, speciesId);
    await insertVisibleProfilePost(client, arbitraryUserId, speciesId);

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body)
        VALUES ($1, $2, $3, 'Thread participant')
      `,
      [parentCommentId, targetPostId, threadUserId],
    );
    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body)
        VALUES ($1, $2, $3, 'Other thread participant')
      `,
      [crypto.randomUUID(), targetPostId, unrelatedThreadUserId],
    );
    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES ($1, $2)
      `,
      [viewerId, followedUserId],
    );

    const emptyQuery = await client.queryObject<MentionSuggestionRow>(
      `
        SELECT user_id, username, source
        FROM public.get_explore_mention_suggestions($1, $2, NULL, '', 10)
      `,
      [viewerId, targetPostId],
    );
    assertEquals(
      emptyQuery.rows.map((row) => row.username),
      ["owner_mention", "thread_mention", "unrelated_mention"],
    );

    const scopedThreadQuery = await client.queryObject<MentionSuggestionRow>(
      `
        SELECT user_id, username, source
        FROM public.get_explore_mention_suggestions($1, $2, $3, '', 10)
      `,
      [viewerId, targetPostId, parentCommentId],
    );
    assertEquals(
      scopedThreadQuery.rows.map((row) => row.username),
      ["owner_mention", "thread_mention"],
    );

    const followedQuery = await client.queryObject<MentionSuggestionRow>(
      `
        SELECT user_id, username, source
        FROM public.get_explore_mention_suggestions($1, $2, NULL, 'fo', 10)
      `,
      [viewerId, targetPostId],
    );
    assertEquals(followedQuery.rows.map((row) => row.username), [
      "followed_mention",
    ]);
    assertEquals(followedQuery.rows[0]?.source, "following");

    const arbitraryQuery = await client.queryObject<MentionSuggestionRow>(
      `
        SELECT user_id, username, source
        FROM public.get_explore_mention_suggestions($1, $2, NULL, 'ar', 10)
      `,
      [viewerId, targetPostId],
    );
    assertEquals(arbitraryQuery.rows.length, 0);
  });
});

Deno.test("Explore mentions DB - body resolution filters blocked/self/global users and dedupes notifications", async () => {
  await withExploreDbTest("exploreMentionsDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const actorId = crypto.randomUUID();
    const followedUserId = crypto.randomUUID();
    const blockedUserId = crypto.randomUUID();
    const arbitraryUserId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const commentId = crypto.randomUUID();

    await insertUser(client, ownerId, "Owner Mentioned");
    await insertUser(client, actorId, "Actor Mentioner");
    await insertUser(client, followedUserId, "Followed Mentioned");
    await insertUser(client, blockedUserId, "Blocked Mentioned");
    await insertUser(client, arbitraryUserId, "Arbitrary Mentioned");
    await setUsername(client, ownerId, "owner_ping");
    await setUsername(client, actorId, "actor_ping");
    await setUsername(client, followedUserId, "followed_ping");
    await setUsername(client, blockedUserId, "blocked_ping");
    await setUsername(client, arbitraryUserId, "arbitrary_ping");
    await insertSpecies(client, speciesId, "Rosa pingaria");

    const targetPostId = await insertVisibleProfilePost(
      client,
      ownerId,
      speciesId,
    );
    await insertVisibleProfilePost(client, followedUserId, speciesId);
    await insertVisibleProfilePost(client, blockedUserId, speciesId);
    await insertVisibleProfilePost(client, arbitraryUserId, speciesId);

    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES ($1, $2), ($1, $3)
      `,
      [actorId, followedUserId, blockedUserId],
    );
    await client.queryArray(
      `
        INSERT INTO public.user_blocks (blocker_id, blocked_id)
        VALUES ($1, $2)
      `,
      [blockedUserId, actorId],
    );

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body)
        VALUES (
          $1,
          $2,
          $3,
          '@owner_ping @followed_ping @followed_ping @blocked_ping @actor_ping @arbitrary_ping'
        )
      `,
      [commentId, targetPostId, actorId],
    );

    const mentions = await client.queryObject<MentionRow>(
      `
        SELECT user_id, username
        FROM public.insert_explore_comment_mentions_from_body($1, $2)
        ORDER BY username
      `,
      [commentId, actorId],
    );
    assertEquals(mentions.rows.map((row) => row.username), [
      "followed_ping",
      "owner_ping",
    ]);

    const notifications = await client.queryObject<NotificationTypeRow>(
      `
        SELECT user_id, type
        FROM public.explore_post_notifications
        WHERE comment_id = $1
          AND type IN ('comment', 'comment_mention')
        ORDER BY type, user_id
      `,
      [commentId],
    );

    assertEquals(
      notifications.rows.map((row) => `${row.user_id}:${row.type}`),
      [
        `${ownerId}:comment`,
        `${followedUserId}:comment_mention`,
      ],
    );
  });
});

Deno.test("Explore mentions DB - mention notifications do not duplicate reply recipients", async () => {
  await withExploreDbTest("exploreMentionsDb.test", async (client: Client) => {
    const ownerId = crypto.randomUUID();
    const parentAuthorId = crypto.randomUUID();
    const actorId = crypto.randomUUID();
    const followedUserId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const parentCommentId = crypto.randomUUID();
    const replyId = crypto.randomUUID();

    await insertUser(client, ownerId, "Reply Owner");
    await insertUser(client, parentAuthorId, "Reply Parent");
    await insertUser(client, actorId, "Reply Actor");
    await insertUser(client, followedUserId, "Reply Followed");
    await setUsername(client, ownerId, "owner_reply_ping");
    await setUsername(client, parentAuthorId, "parent_reply_ping");
    await setUsername(client, followedUserId, "followed_reply_ping");
    await insertSpecies(client, speciesId, "Rosa responsaria");

    const targetPostId = await insertVisibleProfilePost(
      client,
      ownerId,
      speciesId,
    );
    await insertVisibleProfilePost(client, parentAuthorId, speciesId);
    await insertVisibleProfilePost(client, followedUserId, speciesId);

    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES ($1, $2)
      `,
      [actorId, followedUserId],
    );
    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body)
        VALUES ($1, $2, $3, 'Parent')
      `,
      [parentCommentId, targetPostId, parentAuthorId],
    );
    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, parent_comment_id, user_id, body)
        VALUES (
          $1,
          $2,
          $3,
          $4,
          '@owner_reply_ping @parent_reply_ping @followed_reply_ping'
        )
      `,
      [replyId, targetPostId, parentCommentId, actorId],
    );

    await client.queryArray(
      "SELECT * FROM public.insert_explore_comment_mentions_from_body($1, $2)",
      [replyId, actorId],
    );

    const notifications = await client.queryObject<NotificationTypeRow>(
      `
        SELECT user_id, type
        FROM public.explore_post_notifications
        WHERE comment_id = $1
          AND type IN ('comment_reply', 'comment_mention')
        ORDER BY type, user_id
      `,
      [replyId],
    );

    assertEquals(
      new Set(notifications.rows.map((row) => `${row.user_id}:${row.type}`)),
      new Set([
        `${ownerId}:comment_reply`,
        `${parentAuthorId}:comment_reply`,
        `${followedUserId}:comment_mention`,
      ]),
    );
  });
});
