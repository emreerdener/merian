import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const DEFAULT_DB_URL =
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const DB_URL = Deno.env.get("SUPABASE_DB_TEST_URL") ?? DEFAULT_DB_URL;

async function withDbTest(
  fn: (client: Client) => Promise<void>,
): Promise<void> {
  const client = new Client(DB_URL);

  try {
    await client.connect();
  } catch (error) {
    console.warn(
      `[exploreNotificationsDb.test] Skipping DB integration test. Could not connect to ${DB_URL}: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    return;
  }

  try {
    await client.queryArray("BEGIN");
    await fn(client);
  } finally {
    try {
      await client.queryArray("ROLLBACK");
    } catch {
      // Ignore rollback failures during cleanup.
    }
    await client.end();
  }
}

async function insertUser(
  client: Client,
  id: string,
  publicName: string,
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.users (
        id,
        email,
        public_author_name,
        public_identity_source,
        public_username
      )
      VALUES ($1, $2, $3, 'alias', public.build_default_public_username($1::uuid))
    `,
    [
      id,
      `${publicName.toLowerCase().replaceAll(" ", "_")}@example.com`,
      publicName,
    ],
  );
}

async function insertScan(
  client: Client,
  id: string,
  userId: string,
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.scans (
        id,
        user_id,
        image_storage_urls,
        ai_confidence_score
      )
      VALUES ($1, $2, ARRAY['https://media.merian.app/test-image.webp'], 0.91)
    `,
    [id, userId],
  );
}

async function insertExplorePost(
  client: Client,
  id: string,
  userId: string,
  scanId: string,
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.explore_posts (
        id,
        user_id,
        scan_id
      )
      VALUES ($1, $2, $3)
    `,
    [id, userId, scanId],
  );
}

async function seedVisibleExplorePost(
  client: Client,
  ownerName = "Owner Explorer",
): Promise<{ ownerId: string; postId: string; scanId: string }> {
  const ownerId = crypto.randomUUID();
  const scanId = crypto.randomUUID();
  const postId = crypto.randomUUID();

  await insertUser(client, ownerId, ownerName);
  await insertScan(client, scanId, ownerId);
  await insertExplorePost(client, postId, ownerId, scanId);

  return { ownerId, postId, scanId };
}

type NotificationRow = {
  id: string;
  action_count: number;
  is_read: boolean;
  recent_actor_ids: string[];
  triggering_user_id: string | null;
};

async function fetchLikeNotification(
  client: Client,
  ownerId: string,
  postId: string,
): Promise<NotificationRow | null> {
  const result = await client.queryObject<NotificationRow>(
    `
      SELECT
        id,
        action_count,
        is_read,
        recent_actor_ids,
        triggering_user_id
      FROM public.explore_post_notifications
      WHERE user_id = $1
        AND post_id = $2
        AND type = 'like_aggregated'
    `,
    [ownerId, postId],
  );

  return result.rows[0] ?? null;
}

type NotificationFeedRow = {
  notification_id: string;
  post_id: string | null;
  type:
    | "like_aggregated"
    | "comment"
    | "comment_reaction"
    | "comment_reply"
    | "follow";
  comment_id: string | null;
  parent_comment_id: string | null;
  reaction_emoji: string | null;
  recent_actor_names: string[];
  action_count: number;
  triggering_user_name: string | null;
  comment_body: string | null;
  is_read: boolean;
  is_reply_to_viewer_comment: boolean | null;
};

type PushPayloadRow = {
  notification_id: string;
  recipient_user_id: string;
  post_id: string;
  comment_id: string | null;
  parent_comment_id: string | null;
  type: "like_aggregated" | "comment" | "comment_reaction" | "comment_reply";
  action_count: number;
  reaction_emoji: string | null;
  comment_body: string | null;
  triggering_user_name: string | null;
  recent_actor_names: string[];
  is_reply_to_viewer_comment: boolean | null;
  unread_count: number;
};

type NotificationCursorRow = {
  notification_id: string;
  updated_at: string;
  type:
    | "like_aggregated"
    | "comment"
    | "comment_reaction"
    | "comment_reply"
    | "follow";
};

type CommentReactionNotificationRow = {
  id: string;
  action_count: number;
  is_read: boolean;
  recent_actor_ids: string[];
  triggering_user_id: string | null;
  reaction_emoji: string | null;
};

async function fetchCommentReactionNotification(
  client: Client,
  recipientId: string,
  commentId: string,
  emoji: string,
): Promise<CommentReactionNotificationRow | null> {
  const result = await client.queryObject<CommentReactionNotificationRow>(
    `
      SELECT
        id,
        action_count,
        is_read,
        recent_actor_ids,
        triggering_user_id,
        reaction_emoji
      FROM public.explore_post_notifications
      WHERE user_id = $1
        AND comment_id = $2
        AND type = 'comment_reaction'
        AND reaction_emoji = $3
    `,
    [recipientId, commentId, emoji],
  );

  return result.rows[0] ?? null;
}

Deno.test("Explore notifications DB - like aggregation, RPC fetch, mark read, and unlike cleanup", async () => {
  await withDbTest(async (client) => {
    const { ownerId, postId } = await seedVisibleExplorePost(client);
    const likerOneId = crypto.randomUUID();
    const likerTwoId = crypto.randomUUID();

    await insertUser(client, likerOneId, "Liker One");
    await insertUser(client, likerTwoId, "Liker Two");

    await client.queryArray(
      `
        INSERT INTO public.explore_post_likes (post_id, user_id, created_at)
        VALUES ($1, $2, '2026-04-27T10:00:00Z')
      `,
      [postId, likerOneId],
    );

    let notification = await fetchLikeNotification(client, ownerId, postId);
    assertExists(notification);
    assertEquals(notification.action_count, 1);
    assertEquals(notification.is_read, false);
    assertEquals(notification.recent_actor_ids, [likerOneId]);
    assertEquals(notification.triggering_user_id, likerOneId);

    const markReadResult = await client.queryObject<{ count: number }>(
      `SELECT public.mark_explore_notifications_read($1) AS count`,
      [ownerId],
    );
    assertEquals(markReadResult.rows[0]?.count, 1);

    notification = await fetchLikeNotification(client, ownerId, postId);
    assertExists(notification);
    assertEquals(notification.is_read, true);

    await client.queryArray(
      `
        INSERT INTO public.explore_post_likes (post_id, user_id, created_at)
        VALUES ($1, $2, '2026-04-27T10:05:00Z')
      `,
      [postId, likerTwoId],
    );

    notification = await fetchLikeNotification(client, ownerId, postId);
    assertExists(notification);
    assertEquals(notification.action_count, 2);
    assertEquals(notification.is_read, false);
    assertEquals(notification.recent_actor_ids, [likerTwoId, likerOneId]);
    assertEquals(notification.triggering_user_id, likerTwoId);

    const feedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'like_aggregated'
      `,
      [ownerId],
    );
    assertEquals(feedResult.rows.length, 1);
    assertEquals(feedResult.rows[0].recent_actor_names, [
      "Liker Two",
      "Liker One",
    ]);
    assertEquals(feedResult.rows[0].action_count, 2);
    assertEquals(feedResult.rows[0].triggering_user_name, "Liker Two");
    assertEquals(feedResult.rows[0].is_read, false);

    const pushPayloadResult = await client.queryObject<PushPayloadRow>(
      `
        SELECT *
        FROM public.get_explore_push_notification_payload($1)
      `,
      [notification.id],
    );
    assertEquals(pushPayloadResult.rows.length, 1);
    assertEquals(pushPayloadResult.rows[0].post_id, postId);
    assertEquals(pushPayloadResult.rows[0].action_count, 2);
    assertEquals(pushPayloadResult.rows[0].triggering_user_name, "Liker Two");
    assertEquals(pushPayloadResult.rows[0].recent_actor_names, [
      "Liker Two",
      "Liker One",
    ]);
    assertEquals(pushPayloadResult.rows[0].unread_count, 1);

    const unreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [ownerId],
    );
    assertEquals(unreadCountResult.rows[0]?.count, 1);

    await client.queryArray(
      `
        DELETE FROM public.explore_post_likes
        WHERE post_id = $1
          AND user_id = $2
      `,
      [postId, likerOneId],
    );

    notification = await fetchLikeNotification(client, ownerId, postId);
    assertExists(notification);
    assertEquals(notification.action_count, 1);
    assertEquals(notification.recent_actor_ids, [likerTwoId]);

    await client.queryArray(
      `
        DELETE FROM public.explore_post_likes
        WHERE post_id = $1
          AND user_id = $2
      `,
      [postId, likerTwoId],
    );

    notification = await fetchLikeNotification(client, ownerId, postId);
    assertEquals(notification, null);
  });
});

Deno.test("Explore notifications DB - self-like does not create a notification", async () => {
  await withDbTest(async (client) => {
    const { ownerId, postId } = await seedVisibleExplorePost(client);

    await client.queryArray(
      `
        INSERT INTO public.explore_post_likes (post_id, user_id)
        VALUES ($1, $2)
      `,
      [postId, ownerId],
    );

    const notification = await fetchLikeNotification(client, ownerId, postId);
    assertEquals(notification, null);

    const unreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [ownerId],
    );
    assertEquals(unreadCountResult.rows[0]?.count, 0);
  });
});

Deno.test("Explore notifications DB - follow notifications are in-app only and removed on unfollow", async () => {
  await withDbTest(async (client) => {
    const followerId = crypto.randomUUID();
    const followeeId = crypto.randomUUID();

    await insertUser(client, followerId, "New Follower");
    await insertUser(client, followeeId, "Followee Author");

    await client.queryArray(
      `
        INSERT INTO public.user_follows (follower_user_id, followee_user_id)
        VALUES ($1, $2)
      `,
      [followerId, followeeId],
    );

    const feedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'follow'
      `,
      [followeeId],
    );

    assertEquals(feedResult.rows.length, 1);
    assertEquals(feedResult.rows[0].post_id, null);
    assertEquals(feedResult.rows[0].triggering_user_name, "New Follower");
    assertEquals(feedResult.rows[0].recent_actor_names, []);
    assertEquals(feedResult.rows[0].action_count, 1);

    const unreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [followeeId],
    );
    assertEquals(unreadCountResult.rows[0]?.count, 1);

    const pushPayloadResult = await client.queryObject<PushPayloadRow>(
      `
        SELECT *
        FROM public.get_explore_push_notification_payload($1)
      `,
      [feedResult.rows[0].notification_id],
    );
    assertEquals(pushPayloadResult.rows.length, 0);

    await client.queryArray(
      `
        DELETE FROM public.user_follows
        WHERE follower_user_id = $1
          AND followee_user_id = $2
      `,
      [followerId, followeeId],
    );

    const afterUnfollow = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'follow'
      `,
      [followeeId],
    );
    assertEquals(afterUnfollow.rows.length, 0);
  });
});

Deno.test("Explore notifications DB - comment lifecycle suppresses self and recreates on restore", async () => {
  await withDbTest(async (client) => {
    const { ownerId, postId } = await seedVisibleExplorePost(client);
    const commenterId = crypto.randomUUID();
    const commentId = crypto.randomUUID();

    await insertUser(client, commenterId, "Helpful Commenter");

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body)
        VALUES ($1, $2, $3, 'Beautiful find')
      `,
      [commentId, postId, commenterId],
    );

    let feedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment'
      `,
      [ownerId],
    );
    assertEquals(feedResult.rows.length, 1);
    assertEquals(feedResult.rows[0].triggering_user_name, "Helpful Commenter");
    assertEquals(feedResult.rows[0].comment_body, "Beautiful find");
    assertEquals(feedResult.rows[0].action_count, 1);
    const commentNotificationId = feedResult.rows[0].notification_id;

    let pushPayloadResult = await client.queryObject<PushPayloadRow>(
      `
        SELECT *
        FROM public.get_explore_push_notification_payload($1)
      `,
      [commentNotificationId],
    );
    assertEquals(pushPayloadResult.rows.length, 1);
    assertEquals(
      pushPayloadResult.rows[0].triggering_user_name,
      "Helpful Commenter",
    );
    assertEquals(pushPayloadResult.rows[0].comment_body, "Beautiful find");

    await client.queryArray(
      `
        UPDATE public.explore_post_comments
        SET deleted_at = NOW()
        WHERE id = $1
      `,
      [commentId],
    );

    feedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment'
      `,
      [ownerId],
    );
    assertEquals(feedResult.rows.length, 0);

    pushPayloadResult = await client.queryObject<PushPayloadRow>(
      `
        SELECT *
        FROM public.get_explore_push_notification_payload($1)
      `,
      [commentNotificationId],
    );
    assertEquals(pushPayloadResult.rows.length, 0);

    await client.queryArray(
      `
        UPDATE public.explore_post_comments
        SET deleted_at = NULL
        WHERE id = $1
      `,
      [commentId],
    );

    feedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment'
      `,
      [ownerId],
    );
    assertEquals(feedResult.rows.length, 1);

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body)
        VALUES ($1, $2, $3, 'Talking to myself')
      `,
      [crypto.randomUUID(), postId, ownerId],
    );

    const unreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [ownerId],
    );
    assertEquals(unreadCountResult.rows[0]?.count, 1);
  });
});

Deno.test("Explore notifications DB - blocked comment actors are filtered and unshare deletes rows", async () => {
  await withDbTest(async (client) => {
    const { ownerId, postId } = await seedVisibleExplorePost(client);
    const actorId = crypto.randomUUID();
    const commentId = crypto.randomUUID();

    await insertUser(client, actorId, "Blocked Actor");

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body)
        VALUES ($1, $2, $3, 'This should disappear when blocked')
      `,
      [commentId, postId, actorId],
    );

    const commentNotificationResult = await client.queryObject<{ id: string }>(
      `
        SELECT id
        FROM public.explore_post_notifications
        WHERE comment_id = $1
      `,
      [commentId],
    );
    assertEquals(commentNotificationResult.rows.length, 1);

    let unreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [ownerId],
    );
    assertEquals(unreadCountResult.rows[0]?.count, 1);

    await client.queryArray(
      `
        INSERT INTO public.user_blocks (blocker_id, blocked_id)
        VALUES ($1, $2)
      `,
      [ownerId, actorId],
    );

    let feedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment'
      `,
      [ownerId],
    );
    assertEquals(feedResult.rows.length, 0);

    const pushPayloadResult = await client.queryObject<PushPayloadRow>(
      `
        SELECT *
        FROM public.get_explore_push_notification_payload($1)
      `,
      [commentNotificationResult.rows[0].id],
    );
    assertEquals(pushPayloadResult.rows.length, 0);

    unreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [ownerId],
    );
    assertEquals(unreadCountResult.rows[0]?.count, 0);

    await client.queryArray(
      `
        DELETE FROM public.user_blocks
        WHERE blocker_id = $1
          AND blocked_id = $2
      `,
      [ownerId, actorId],
    );

    await client.queryArray(
      `
        UPDATE public.explore_posts
        SET unshared_at = NOW()
        WHERE id = $1
      `,
      [postId],
    );

    const notificationCountResult = await client.queryObject<{ count: number }>(
      `
        SELECT COUNT(*)::INT AS count
        FROM public.explore_post_notifications
        WHERE user_id = $1
      `,
      [ownerId],
    );
    assertEquals(notificationCountResult.rows[0]?.count, 0);
  });
});

Deno.test("Explore notifications DB - comment replies notify parent author and distinct post owner", async () => {
  await withDbTest(async (client) => {
    const { ownerId, postId } = await seedVisibleExplorePost(client);
    const parentAuthorId = crypto.randomUUID();
    const replierId = crypto.randomUUID();
    const parentCommentId = crypto.randomUUID();
    const replyId = crypto.randomUUID();

    await insertUser(client, parentAuthorId, "Parent Author");
    await insertUser(client, replierId, "Reply Author");

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body, created_at)
        VALUES ($1, $2, $3, 'What a find', '2026-05-19T10:00:00Z')
      `,
      [parentCommentId, postId, parentAuthorId],
    );

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, parent_comment_id, user_id, body, created_at)
        VALUES ($1, $2, $3, $4, 'Agreed, this is lovely', '2026-05-19T10:01:00Z')
      `,
      [replyId, postId, parentCommentId, replierId],
    );

    const parentFeedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment_reply'
      `,
      [parentAuthorId],
    );
    assertEquals(parentFeedResult.rows.length, 1);
    assertEquals(parentFeedResult.rows[0].comment_id, replyId);
    assertEquals(parentFeedResult.rows[0].parent_comment_id, parentCommentId);
    assertEquals(parentFeedResult.rows[0].triggering_user_name, "Reply Author");
    assertEquals(
      parentFeedResult.rows[0].comment_body,
      "Agreed, this is lovely",
    );
    assertEquals(parentFeedResult.rows[0].is_reply_to_viewer_comment, true);

    const ownerFeedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment_reply'
      `,
      [ownerId],
    );
    assertEquals(ownerFeedResult.rows.length, 1);
    assertEquals(ownerFeedResult.rows[0].comment_id, replyId);
    assertEquals(ownerFeedResult.rows[0].parent_comment_id, parentCommentId);
    assertEquals(ownerFeedResult.rows[0].is_reply_to_viewer_comment, false);

    const parentPushPayloadResult = await client.queryObject<PushPayloadRow>(
      `
        SELECT *
        FROM public.get_explore_push_notification_payload($1)
      `,
      [parentFeedResult.rows[0].notification_id],
    );
    assertEquals(parentPushPayloadResult.rows.length, 1);
    assertEquals(parentPushPayloadResult.rows[0].type, "comment_reply");
    assertEquals(parentPushPayloadResult.rows[0].comment_id, replyId);
    assertEquals(
      parentPushPayloadResult.rows[0].parent_comment_id,
      parentCommentId,
    );
    assertEquals(
      parentPushPayloadResult.rows[0].is_reply_to_viewer_comment,
      true,
    );

    await client.queryArray(
      `
        UPDATE public.explore_post_comments
        SET deleted_at = NOW()
        WHERE id = $1
      `,
      [parentCommentId],
    );

    const hiddenParentFeedResult = await client.queryObject<
      NotificationFeedRow
    >(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment_reply'
      `,
      [parentAuthorId],
    );
    assertEquals(hiddenParentFeedResult.rows.length, 0);

    const unreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [parentAuthorId],
    );
    assertEquals(unreadCountResult.rows[0]?.count, 0);
  });
});

Deno.test("Explore notifications DB - comment reactions notify comment authors, aggregate by emoji, and hide with the comment", async () => {
  await withDbTest(async (client) => {
    const { ownerId, postId } = await seedVisibleExplorePost(client);
    const commenterId = crypto.randomUUID();
    const reactorOneId = crypto.randomUUID();
    const reactorTwoId = crypto.randomUUID();
    const commentId = crypto.randomUUID();

    await insertUser(client, commenterId, "Insightful Commenter");
    await insertUser(client, reactorOneId, "Reaction One");
    await insertUser(client, reactorTwoId, "Reaction Two");

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body)
        VALUES ($1, $2, $3, 'I saw one of these near the trail too')
      `,
      [commentId, postId, commenterId],
    );

    await client.queryArray(
      `
        INSERT INTO public.explore_comment_reactions (comment_id, user_id, emoji, created_at)
        VALUES ($1, $2, '🔥', '2026-05-05T10:00:00Z')
      `,
      [commentId, reactorOneId],
    );

    let reactionNotification = await fetchCommentReactionNotification(
      client,
      commenterId,
      commentId,
      "🔥",
    );
    assertExists(reactionNotification);
    assertEquals(reactionNotification.action_count, 1);
    assertEquals(reactionNotification.is_read, false);
    assertEquals(reactionNotification.recent_actor_ids, [reactorOneId]);
    assertEquals(reactionNotification.triggering_user_id, reactorOneId);
    assertEquals(reactionNotification.reaction_emoji, "🔥");

    let feedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment_reaction'
      `,
      [commenterId],
    );
    assertEquals(feedResult.rows.length, 1);
    assertEquals(feedResult.rows[0].reaction_emoji, "🔥");
    assertEquals(feedResult.rows[0].recent_actor_names, ["Reaction One"]);
    assertEquals(feedResult.rows[0].triggering_user_name, "Reaction One");
    assertEquals(
      feedResult.rows[0].comment_body,
      "I saw one of these near the trail too",
    );

    let pushPayloadResult = await client.queryObject<PushPayloadRow>(
      `
        SELECT *
        FROM public.get_explore_push_notification_payload($1)
      `,
      [reactionNotification.id],
    );
    assertEquals(pushPayloadResult.rows.length, 1);
    assertEquals(pushPayloadResult.rows[0].recipient_user_id, commenterId);
    assertEquals(pushPayloadResult.rows[0].reaction_emoji, "🔥");
    assertEquals(
      pushPayloadResult.rows[0].triggering_user_name,
      "Reaction One",
    );

    const markReadResult = await client.queryObject<{ count: number }>(
      `SELECT public.mark_explore_notifications_read($1) AS count`,
      [commenterId],
    );
    assertEquals(markReadResult.rows[0]?.count, 1);

    reactionNotification = await fetchCommentReactionNotification(
      client,
      commenterId,
      commentId,
      "🔥",
    );
    assertExists(reactionNotification);
    assertEquals(reactionNotification.is_read, true);

    await client.queryArray(
      `
        INSERT INTO public.explore_comment_reactions (comment_id, user_id, emoji, created_at)
        VALUES ($1, $2, '🔥', '2026-05-05T10:05:00Z')
      `,
      [commentId, commenterId],
    );

    reactionNotification = await fetchCommentReactionNotification(
      client,
      commenterId,
      commentId,
      "🔥",
    );
    assertExists(reactionNotification);
    assertEquals(reactionNotification.action_count, 1);
    assertEquals(reactionNotification.is_read, true);
    assertEquals(reactionNotification.recent_actor_ids, [reactorOneId]);

    await client.queryArray(
      `
        INSERT INTO public.explore_comment_reactions (comment_id, user_id, emoji, created_at)
        VALUES ($1, $2, '🔥', '2026-05-05T10:06:00Z')
      `,
      [commentId, reactorTwoId],
    );

    reactionNotification = await fetchCommentReactionNotification(
      client,
      commenterId,
      commentId,
      "🔥",
    );
    assertExists(reactionNotification);
    assertEquals(reactionNotification.action_count, 2);
    assertEquals(reactionNotification.is_read, false);
    assertEquals(reactionNotification.recent_actor_ids, [
      reactorTwoId,
      reactorOneId,
    ]);
    assertEquals(reactionNotification.triggering_user_id, reactorTwoId);

    await client.queryArray(
      `
        UPDATE public.explore_post_notifications
        SET is_read = TRUE
        WHERE id = $1
      `,
      [reactionNotification.id],
    );

    await client.queryArray(
      `
        DELETE FROM public.explore_comment_reactions
        WHERE comment_id = $1
          AND user_id = $2
          AND emoji = '🔥'
      `,
      [commentId, reactorOneId],
    );

    reactionNotification = await fetchCommentReactionNotification(
      client,
      commenterId,
      commentId,
      "🔥",
    );
    assertExists(reactionNotification);
    assertEquals(reactionNotification.action_count, 1);
    assertEquals(reactionNotification.is_read, true);
    assertEquals(reactionNotification.recent_actor_ids, [reactorTwoId]);

    await client.queryArray(
      `
        UPDATE public.explore_post_comments
        SET deleted_at = NOW()
        WHERE id = $1
      `,
      [commentId],
    );

    feedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment_reaction'
      `,
      [commenterId],
    );
    assertEquals(feedResult.rows.length, 0);

    pushPayloadResult = await client.queryObject<PushPayloadRow>(
      `
        SELECT *
        FROM public.get_explore_push_notification_payload($1)
      `,
      [reactionNotification.id],
    );
    assertEquals(pushPayloadResult.rows.length, 0);

    await client.queryArray(
      `
        UPDATE public.explore_post_comments
        SET deleted_at = NULL
        WHERE id = $1
      `,
      [commentId],
    );

    reactionNotification = await fetchCommentReactionNotification(
      client,
      commenterId,
      commentId,
      "🔥",
    );
    assertExists(reactionNotification);
    assertEquals(reactionNotification.action_count, 1);
    assertEquals(reactionNotification.is_read, false);

    await client.queryArray(
      `
        DELETE FROM public.explore_comment_reactions
        WHERE comment_id = $1
          AND user_id = $2
          AND emoji = '🔥'
      `,
      [commentId, reactorTwoId],
    );

    reactionNotification = await fetchCommentReactionNotification(
      client,
      commenterId,
      commentId,
      "🔥",
    );
    assertEquals(reactionNotification, null);

    const ownerUnreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [ownerId],
    );
    assertEquals(ownerUnreadCountResult.rows[0]?.count, 1);
  });
});

Deno.test("Explore notifications DB - blocked reaction actors are filtered out of comment reaction notifications", async () => {
  await withDbTest(async (client) => {
    const { ownerId, postId } = await seedVisibleExplorePost(client);
    const commenterId = crypto.randomUUID();
    const reactorId = crypto.randomUUID();
    const commentId = crypto.randomUUID();

    await insertUser(client, commenterId, "Blocked Reaction Recipient");
    await insertUser(client, reactorId, "Blocked Reactor");

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body)
        VALUES ($1, $2, $3, 'Comment waiting for reactions')
      `,
      [commentId, postId, commenterId],
    );

    await client.queryArray(
      `
        INSERT INTO public.explore_comment_reactions (comment_id, user_id, emoji)
        VALUES ($1, $2, '👏')
      `,
      [commentId, reactorId],
    );

    const reactionNotification = await fetchCommentReactionNotification(
      client,
      commenterId,
      commentId,
      "👏",
    );
    assertExists(reactionNotification);

    let unreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [commenterId],
    );
    assertEquals(unreadCountResult.rows[0]?.count, 1);

    await client.queryArray(
      `
        INSERT INTO public.user_blocks (blocker_id, blocked_id)
        VALUES ($1, $2)
      `,
      [commenterId, reactorId],
    );

    const feedResult = await client.queryObject<NotificationFeedRow>(
      `
        SELECT *
        FROM public.get_explore_notifications($1, 50, NULL, NULL)
        WHERE type = 'comment_reaction'
      `,
      [commenterId],
    );
    assertEquals(feedResult.rows.length, 0);

    const pushPayloadResult = await client.queryObject<PushPayloadRow>(
      `
        SELECT *
        FROM public.get_explore_push_notification_payload($1)
      `,
      [reactionNotification.id],
    );
    assertEquals(pushPayloadResult.rows.length, 0);

    unreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [commenterId],
    );
    assertEquals(unreadCountResult.rows[0]?.count, 0);

    const ownerUnreadCountResult = await client.queryObject<{ count: number }>(
      `SELECT public.get_unread_explore_notification_count($1) AS count`,
      [ownerId],
    );
    assertEquals(ownerUnreadCountResult.rows[0]?.count, 1);
  });
});

Deno.test("Explore notifications DB - cursor pagination preserves stable ordering across updated_at ties", async () => {
  await withDbTest(async (client) => {
    const { ownerId, postId } = await seedVisibleExplorePost(
      client,
      "Cursor Owner",
    );
    const actorOneId = crypto.randomUUID();
    const actorTwoId = crypto.randomUUID();
    const actorThreeId = crypto.randomUUID();
    const commentOneId = crypto.randomUUID();
    const commentTwoId = crypto.randomUUID();

    await insertUser(client, actorOneId, "Cursor Actor One");
    await insertUser(client, actorTwoId, "Cursor Actor Two");
    await insertUser(client, actorThreeId, "Cursor Actor Three");

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body, created_at)
        VALUES
          ($1, $2, $3, 'First cursor comment', '2026-04-28T12:00:00Z'),
          ($4, $2, $5, 'Second cursor comment', '2026-04-28T12:01:00Z')
      `,
      [commentOneId, postId, actorOneId, commentTwoId, actorTwoId],
    );

    const notificationIdOne = "00000000-0000-0000-0000-000000000010";
    const notificationIdTwo = "00000000-0000-0000-0000-000000000020";
    const notificationIdThree = "00000000-0000-0000-0000-000000000030";

    await client.queryArray(
      `
        INSERT INTO public.explore_post_notifications (
          id,
          user_id,
          post_id,
          type,
          comment_id,
          triggering_user_id,
          recent_actor_ids,
          action_count,
          is_read,
          created_at,
          updated_at
        )
        VALUES
          (
            $1,
            $2,
            $3,
            'comment',
            $4,
            $5,
            ARRAY[]::UUID[],
            1,
            FALSE,
            '2026-04-28T12:00:00Z',
            '2026-04-28T12:10:00Z'
          ),
          (
            $6,
            $2,
            $3,
            'comment',
            $7,
            $8,
            ARRAY[]::UUID[],
            1,
            FALSE,
            '2026-04-28T12:01:00Z',
            '2026-04-28T12:10:00Z'
          ),
          (
            $9,
            $2,
            $3,
            'like_aggregated',
            NULL,
            $10,
            ARRAY[$10, $5]::UUID[],
            2,
            FALSE,
            '2026-04-28T11:59:00Z',
            '2026-04-28T12:05:00Z'
          )
      `,
      [
        notificationIdOne,
        ownerId,
        postId,
        commentOneId,
        actorOneId,
        notificationIdTwo,
        commentTwoId,
        actorTwoId,
        notificationIdThree,
        actorThreeId,
      ],
    );

    const firstPage = await client.queryObject<NotificationCursorRow>(
      `
        SELECT notification_id, updated_at::text AS updated_at, type
        FROM public.get_explore_notifications($1, 2, NULL, NULL)
      `,
      [ownerId],
    );

    assertEquals(
      firstPage.rows.map((row) => row.notification_id),
      [notificationIdTwo, notificationIdOne],
    );

    const cursor = firstPage.rows[1];
    const secondPage = await client.queryObject<NotificationCursorRow>(
      `
        SELECT notification_id, updated_at::text AS updated_at, type
        FROM public.get_explore_notifications($1, 2, $2::timestamptz, $3::uuid)
      `,
      [ownerId, cursor.updated_at, cursor.notification_id],
    );

    assertEquals(
      secondPage.rows.map((row) => row.notification_id),
      [notificationIdThree],
    );
  });
});
