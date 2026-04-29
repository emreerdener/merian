import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

type ExploreCommentRow = {
  comment_id: string;
  created_at: string;
  author_user_id: string;
};

Deno.test("Explore comments DB - cursor pagination preserves stable ordering across created_at ties", async () => {
  await withExploreDbTest("exploreCommentsDb.test", async (client: Client) => {
    const viewerId = crypto.randomUUID();
    const ownerId = crypto.randomUUID();
    const authorOneId = crypto.randomUUID();
    const authorTwoId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, viewerId, "Comments Viewer");
    await insertUser(client, ownerId, "Comments Owner");
    await insertUser(client, authorOneId, "Comments Author One");
    await insertUser(client, authorTwoId, "Comments Author Two");
    await insertSpecies(client, speciesId, "Rosa commentaria");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
    });
    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
      sharedAt: "2026-04-28T12:00:00.000Z",
    });

    const commentIds = [
      "00000000-0000-0000-0000-000000000010",
      "00000000-0000-0000-0000-000000000020",
      "00000000-0000-0000-0000-000000000030",
      "00000000-0000-0000-0000-000000000040",
    ];

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body, created_at)
        VALUES
          ($1, $2, $3, 'Comment one', '2026-04-28T10:00:00Z'),
          ($4, $2, $5, 'Comment two', '2026-04-28T10:00:00Z'),
          ($6, $2, $3, 'Comment three', '2026-04-28T10:05:00Z'),
          ($7, $2, $5, 'Comment four', '2026-04-28T10:10:00Z')
      `,
      [commentIds[0], postId, authorOneId, commentIds[1], authorTwoId, commentIds[2], commentIds[3]],
    );

    const firstPage = await client.queryObject<ExploreCommentRow>(
      `
        SELECT comment_id, created_at::text AS created_at, author_user_id
        FROM public.get_explore_comments($1, $2, 2, NULL, NULL)
      `,
      [viewerId, postId],
    );

    assertEquals(
      firstPage.rows.map((row) => row.comment_id),
      [commentIds[0], commentIds[1]],
    );

    const cursor = firstPage.rows[1];
    const secondPage = await client.queryObject<ExploreCommentRow>(
      `
        SELECT comment_id, created_at::text AS created_at, author_user_id
        FROM public.get_explore_comments($1, $2, 2, $3::timestamptz, $4::uuid)
      `,
      [viewerId, postId, cursor.created_at, cursor.comment_id],
    );

    assertEquals(
      secondPage.rows.map((row) => row.comment_id),
      [commentIds[2], commentIds[3]],
    );
  });
});

Deno.test("Explore comments DB - blocked authors are filtered and hidden posts stop returning comments", async () => {
  await withExploreDbTest("exploreCommentsDb.test", async (client: Client) => {
    const viewerId = crypto.randomUUID();
    const ownerId = crypto.randomUUID();
    const visibleAuthorId = crypto.randomUUID();
    const blockedAuthorId = crypto.randomUUID();
    const speciesId = crypto.randomUUID();
    const scanId = crypto.randomUUID();
    const postId = crypto.randomUUID();

    await insertUser(client, viewerId, "Comments Viewer");
    await insertUser(client, ownerId, "Comments Owner");
    await insertUser(client, visibleAuthorId, "Visible Commenter");
    await insertUser(client, blockedAuthorId, "Blocked Commenter");
    await insertSpecies(client, speciesId, "Rosa blockata");

    await insertScan(client, {
      id: scanId,
      userId: ownerId,
      speciesId,
      latitude: 30.2672,
      longitude: -97.7431,
      geoprivacy: "open",
    });
    await insertExplorePost(client, {
      id: postId,
      userId: ownerId,
      scanId,
    });

    await client.queryArray(
      `
        INSERT INTO public.explore_post_comments (id, post_id, user_id, body, created_at)
        VALUES
          ($1, $2, $3, 'Visible comment', '2026-04-28T11:00:00Z'),
          ($4, $2, $5, 'Blocked comment', '2026-04-28T11:05:00Z')
      `,
      [crypto.randomUUID(), postId, visibleAuthorId, crypto.randomUUID(), postId, blockedAuthorId],
    );

    await client.queryArray(
      `
        INSERT INTO public.user_blocks (blocker_id, blocked_id)
        VALUES ($1, $2)
      `,
      [viewerId, blockedAuthorId],
    );

    const visibleRows = await client.queryObject<ExploreCommentRow>(
      `
        SELECT comment_id, created_at::text AS created_at, author_user_id
        FROM public.get_explore_comments($1, $2, 50, NULL, NULL)
      `,
      [viewerId, postId],
    );

    assertEquals(visibleRows.rows.length, 1);
    assertEquals(visibleRows.rows[0].author_user_id, visibleAuthorId);

    await client.queryArray(
      `
        UPDATE public.explore_posts
        SET unshared_at = NOW()
        WHERE id = $1
      `,
      [postId],
    );

    const hiddenRows = await client.queryObject<ExploreCommentRow>(
      `
        SELECT comment_id, created_at::text AS created_at, author_user_id
        FROM public.get_explore_comments($1, $2, 50, NULL, NULL)
      `,
      [viewerId, postId],
    );

    assertEquals(hiddenRows.rows.length, 0);
  });
});
