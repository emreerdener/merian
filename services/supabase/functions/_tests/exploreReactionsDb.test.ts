import { assertEquals, assertRejects } from "@std/assert";
import {
  insertExplorePost,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import type {
  ReactionPage,
  ReactionState,
} from "../_shared/exploreReactions.ts";

async function fixtures(client: Client) {
  const [owner, viewer, second, species, scan, post, comment] = Array.from({
    length: 7,
  }, () => crypto.randomUUID());
  await insertUser(client, owner, "Reaction Owner");
  await insertUser(client, viewer, "Reaction Viewer");
  await insertUser(client, second, "Second Reactor");
  await insertSpecies(client, species, `Reactio testensis ${species}`);
  await client.queryArray(
    `INSERT INTO public.scans(id,user_id,species_id,image_storage_urls,ai_confidence_score,geoprivacy)
    VALUES($1,$2,$3,ARRAY['https://media.example.invalid/reaction.webp'],0.9,'open')`,
    [scan, owner, species],
  );
  await insertExplorePost(client, {
    id: post,
    userId: owner,
    scanId: scan,
    sharedAt: "2026-09-18T00:00:00Z",
  });
  await client.queryArray(
    `INSERT INTO public.explore_post_comments(id,post_id,user_id,body) VALUES($1,$2,$3,'Fixture comment')`,
    [comment, post, owner],
  );
  return { owner, viewer, second, species, post, comment };
}
async function set(
  client: Client,
  viewer: string,
  kind: string,
  id: string,
  emoji: string,
  selected = true,
) {
  const result = await client.queryObject<{ state: ReactionState }>(
    "SELECT public.set_explore_reaction($1,$2,$3,$4,$5) AS state",
    [viewer, kind, id, emoji, selected],
  );
  return result.rows[0].state;
}
Deno.test("Explore reactions DB: idempotence, multiple reactions, heart mapping, comment aliases", async () => {
  await withExploreDbTest("exploreReactionsDb", async (client) => {
    const f = await fixtures(client);
    await client.queryArray("SET LOCAL ROLE service_role");
    assertEquals(
      (await set(client, f.viewer, "post", f.post, "😂")).reaction.count,
      1,
    );
    assertEquals(
      (await set(client, f.viewer, "post", f.post, "😂")).reaction.count,
      1,
    );
    assertEquals(
      (await set(client, f.second, "post", f.post, "😂")).reaction.count,
      2,
    );
    assertEquals(
      (await set(client, f.viewer, "post", f.post, "👍🏽")).reaction.count,
      1,
    );
    assertEquals(
      (await set(client, f.viewer, "post", f.post, "😂", false)).reaction.count,
      1,
    );
    assertEquals(
      (await set(client, f.viewer, "post", f.post, "❤")).like_count,
      1,
    );
    assertEquals(
      (await set(client, f.viewer, "post", f.post, "❤️")).like_count,
      1,
    );
    assertEquals(
      (await set(client, f.viewer, "comment", f.comment, "❤")).reaction.emoji,
      "❤️",
    );
    assertEquals(
      (await set(client, f.viewer, "comment", f.comment, "❤️")).reaction.count,
      1,
    );
    assertEquals(
      (await set(client, f.viewer, "comment", f.comment, "❤", false)).reaction
        .count,
      0,
    );
  });
});
Deno.test("Explore reactions DB: activity capability, grouping, self suppression and removals", async () => {
  await withExploreDbTest("exploreReactionsDb", async (client) => {
    const f = await fixtures(client);
    await client.queryArray("SET LOCAL ROLE service_role");
    await set(client, f.owner, "post", f.post, "😂");
    let rows = await client.queryObject(
      "SELECT * FROM public.get_explore_notifications_with_reactions($1)",
      [f.owner],
    );
    assertEquals(rows.rows.length, 0);
    await set(client, f.viewer, "post", f.post, "😂");
    await set(client, f.second, "post", f.post, "😂");
    rows = await client.queryObject(
      "SELECT * FROM public.get_explore_notifications($1)",
      [f.owner],
    );
    assertEquals(rows.rows.length, 0);
    const legacyCount = await client.queryObject<{ n: number }>(
      "SELECT public.get_unread_explore_notification_count($1) AS n",
      [f.owner],
    );
    assertEquals(legacyCount.rows[0].n, 0);
    const modern = await client.queryObject<
      { type: string; action_count: number; is_read: boolean }
    >("SELECT * FROM public.get_explore_notifications_with_reactions($1)", [
      f.owner,
    ]);
    assertEquals(modern.rows.map((r) => [r.type, r.action_count, r.is_read]), [[
      "post_reaction",
      2,
      false,
    ]]);
    await client.queryArray(
      "SELECT public.mark_explore_notifications_read($1)",
      [f.owner],
    );
    const count = await client.queryObject<{ n: number }>(
      "SELECT public.get_unread_explore_notification_count_with_reactions($1) AS n",
      [f.owner],
    );
    assertEquals(count.rows[0].n, 1);
    await client.queryArray(
      "SELECT public.mark_explore_notifications_read_with_reactions($1)",
      [f.owner],
    );
    await set(client, f.viewer, "post", f.post, "😂", false);
    const removed = await client.queryObject<
      { action_count: number; is_read: boolean }
    >("SELECT * FROM public.get_explore_notifications_with_reactions($1)", [
      f.owner,
    ]);
    assertEquals(removed.rows.map((r) => [r.action_count, r.is_read]), [[
      1,
      true,
    ]]);
    await set(client, f.second, "post", f.post, "😂", false);
    rows = await client.queryObject(
      "SELECT * FROM public.get_explore_notifications_with_reactions($1)",
      [f.owner],
    );
    assertEquals(rows.rows.length, 0);
  });
});
Deno.test("Explore reactions DB: pagination and denied targets", async () => {
  await withExploreDbTest("exploreReactionsDb", async (client) => {
    const f = await fixtures(client);
    const emojis = await client.queryObject<{ emoji: string }>(
      "SELECT emoji FROM internal.explore_emoji_catalog ORDER BY ordinal LIMIT 15",
    );
    for (const row of emojis.rows) {
      await set(client, f.viewer, "post", f.post, row.emoji);
    }
    const first = await client.queryObject<{ page: ReactionPage }>(
      "SELECT public.get_explore_reactions($1,'post',$2,-1,12) AS page",
      [f.viewer, f.post],
    );
    assertEquals(first.rows[0].page.reactions.length, 12);
    const next = await client.queryObject<{ page: ReactionPage }>(
      "SELECT public.get_explore_reactions($1,'post',$2,$3,32) AS page",
      [f.viewer, f.post, first.rows[0].page.reactions_next_cursor],
    );
    assertEquals(next.rows[0].page.reactions.length, 3);
    assertEquals(next.rows[0].page.reactions_next_cursor, null);
    await client.queryArray("SAVEPOINT denied");
    await assertRejects(() => set(client, f.viewer, "post", f.post, "text"));
    await client.queryArray("ROLLBACK TO SAVEPOINT denied");
    await client.queryArray(
      "INSERT INTO public.user_blocks(blocker_id,blocked_id) VALUES($1,$2)",
      [f.owner, f.viewer],
    );
    await client.queryArray("SAVEPOINT blocked");
    await assertRejects(() => set(client, f.viewer, "post", f.post, "😂"));
    await client.queryArray("ROLLBACK TO SAVEPOINT blocked");
    await client.queryArray("SET LOCAL ROLE authenticated");
    await assertRejects(() => set(client, f.second, "post", f.post, "😂"));
  });
});

Deno.test("Explore reactions DB: catalog parity and live actor visibility", async () => {
  await withExploreDbTest("exploreReactionsDb", async (client) => {
    const catalog =
      (await import("../_shared/emojiCatalog.json", { with: { type: "json" } }))
        .default;
    const seeded = await client.queryObject<
      { emoji: string; ordinal: number; aliases: string[] }
    >(
      "SELECT emoji, ordinal, aliases FROM internal.explore_emoji_catalog ORDER BY ordinal",
    );
    assertEquals(
      seeded.rows,
      catalog.entries.map((e) => ({
        emoji: e.emoji,
        ordinal: e.order,
        aliases: e.aliases,
      })),
    );
    const f = await fixtures(client);
    await set(client, f.viewer, "post", f.post, "😂");
    await set(client, f.second, "post", f.post, "😂");
    await client.queryArray(
      "SELECT public.mark_explore_notifications_read_with_reactions($1)",
      [f.owner],
    );
    await set(client, f.owner, "post", f.post, "😂");
    let activity = await client.queryObject<
      { action_count: number; is_read: boolean }
    >(
      "SELECT * FROM public.get_explore_notifications_with_reactions($1)",
      [f.owner],
    );
    assertEquals(activity.rows.map((r) => [r.action_count, r.is_read]), [[
      2,
      true,
    ]]);
    await client.queryArray(
      "INSERT INTO public.user_blocks(blocker_id,blocked_id) VALUES($1,$2)",
      [f.owner, f.viewer],
    );
    activity = await client.queryObject(
      "SELECT * FROM public.get_explore_notifications_with_reactions($1)",
      [f.owner],
    );
    assertEquals(activity.rows[0].action_count, 1);
    await client.queryArray(
      "UPDATE public.users SET is_shadowbanned=true WHERE id=$1",
      [f.second],
    );
    activity = await client.queryObject(
      "SELECT * FROM public.get_explore_notifications_with_reactions($1)",
      [f.owner],
    );
    assertEquals(activity.rows.length, 0);
    await client.queryArray(
      "UPDATE public.explore_posts SET moderated_at=now() WHERE id=$1",
      [f.post],
    );
    await client.queryArray("SAVEPOINT unavailable");
    await assertRejects(() => set(client, f.owner, "post", f.post, "😂"));
    await client.queryArray("ROLLBACK TO SAVEPOINT unavailable");
    await client.queryArray("DELETE FROM public.explore_posts WHERE id=$1", [
      f.post,
    ]);
    const remaining = await client.queryObject(
      "SELECT * FROM public.explore_post_reactions WHERE post_id=$1",
      [f.post],
    );
    assertEquals(remaining.rows.length, 0);
  });
});

Deno.test("Explore reactions DB: moderated comments and ghost conflicts", async () => {
  await withExploreDbTest("exploreReactionsDb", async (client) => {
    const f = await fixtures(client);
    await set(client, f.viewer, "post", f.post, "😂");
    await set(client, f.second, "post", f.post, "😂");
    await client.queryArray(
      "SELECT internal.merge_ghost_social_conflicts($1,$2)",
      [f.viewer, f.second],
    );
    const duplicates = await client.queryObject(
      "SELECT * FROM public.explore_post_reactions WHERE post_id=$1",
      [f.post],
    );
    assertEquals(duplicates.rows.length, 1);
    await client.queryArray(
      "UPDATE public.explore_post_comments SET moderated_at=now() WHERE id=$1",
      [f.comment],
    );
    await client.queryArray("SAVEPOINT unavailable");
    await assertRejects(() =>
      set(client, f.viewer, "comment", f.comment, "❤️")
    );
    await client.queryArray("ROLLBACK TO SAVEPOINT unavailable");
    await client.queryArray(
      "UPDATE public.explore_post_comments SET moderated_at=NULL,deleted_at=now() WHERE id=$1",
      [f.comment],
    );
    await assertRejects(() =>
      set(client, f.viewer, "comment", f.comment, "❤️")
    );
  });
});

Deno.test("Explore reactions DB: concurrent actors and duplicate deliveries serialize", async () => {
  await withExploreDbTest("exploreReactionsDb", async (admin) => {
    const f = await fixtures(admin);
    await admin.queryArray("COMMIT");
    const url = Deno.env.get("SUPABASE_DB_TEST_URL") ??
      "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
    const clients = [new Client(url), new Client(url), new Client(url)];
    try {
      await Promise.all(clients.map(async (c) => {
        await c.connect();
        await c.queryArray("SET ROLE service_role");
      }));
      await Promise.all([
        set(clients[0], f.viewer, "post", f.post, "😂"),
        set(clients[1], f.second, "post", f.post, "😂"),
        set(clients[2], f.viewer, "post", f.post, "😂"),
      ]);
      const final = await set(clients[0], f.viewer, "post", f.post, "😂");
      assertEquals(final.reaction.count, 2);
      const activity = await admin.queryObject<{ action_count: number }>(
        "SELECT * FROM public.get_explore_notifications_with_reactions($1)",
        [f.owner],
      );
      assertEquals(activity.rows[0].action_count, 2);
    } finally {
      await Promise.all(clients.map((c) => c.end()));
      await admin.queryArray(
        "DELETE FROM public.users WHERE id=ANY($1::uuid[])",
        [[f.owner, f.viewer, f.second]],
      );
      await admin.queryArray(
        "DELETE FROM auth.users WHERE id=ANY($1::uuid[])",
        [[f.owner, f.viewer, f.second]],
      );
      await admin.queryArray(
        "DELETE FROM public.species_dictionary WHERE id=$1",
        [
          f.species,
        ],
      );
    }
  });
});

async function people(
  client: Client,
  viewer: string,
  post: string,
  cursor: string | null = null,
) {
  const result = await client.queryObject<
    {
      page:
        import("../get-explore-post-reactors/types.ts").ExplorePostReactorsPage;
    }
  >(
    "SELECT public.get_explore_post_reactors($1,$2,$3) AS page",
    [viewer, post, cursor],
  );
  return result.rows[0].page;
}

Deno.test("Explore reactors DB: unique people include likes and owner, identities and visibility agree", async () => {
  await withExploreDbTest("exploreReactorsDb", async (client) => {
    const f = await fixtures(client);
    await client.queryArray("SET LOCAL ROLE service_role");
    assertEquals((await people(client, f.viewer, f.post)).total_count, 0);
    await set(client, f.owner, "post", f.post, "❤️");
    await set(client, f.viewer, "post", f.post, "❤️");
    await set(client, f.viewer, "post", f.post, "😂");
    await set(client, f.viewer, "post", f.post, "👩🏽‍🔬");
    await set(client, f.second, "post", f.post, "👍🏽");
    let page = await people(client, f.viewer, f.post);
    assertEquals(page.total_count, 3);
    assertEquals(page.reactors.length, 3);
    const viewer = page.reactors.find((p) => p.user_id === f.viewer)!;
    assertEquals(viewer.display_name, "Reaction Viewer");
    assertEquals(viewer.avatar_url, null);
    assertEquals([...viewer.emojis].sort(), ["❤️", "😂", "👩🏽‍🔬"].sort());
    assertEquals(
      page.preview_names,
      page.reactors.slice(0, 2).map((p) => p.display_name),
    );
    await client.queryArray("RESET ROLE");
    await client.queryArray(
      "INSERT INTO public.user_blocks(blocker_id,blocked_id) VALUES($1,$2)",
      [f.second, f.viewer],
    );
    await client.queryArray("SET LOCAL ROLE service_role");
    page = await people(client, f.viewer, f.post);
    assertEquals(page.total_count, 2);
    assertEquals(page.reactors.some((p) => p.user_id === f.second), false);
    assertEquals(page.preview_names.includes("Second Reactor"), false);
    await client.queryArray("RESET ROLE");
    await client.queryArray(
      "DELETE FROM public.user_blocks WHERE blocker_id=$1",
      [f.second],
    );
    await client.queryArray(
      "UPDATE public.users SET is_shadowbanned=true WHERE id=$1",
      [f.second],
    );
    await client.queryArray("SET LOCAL ROLE service_role");
    page = await people(client, f.viewer, f.post);
    assertEquals(page.total_count, 2);
    assertEquals(page.preview_names.includes("Second Reactor"), false);
    await set(client, f.viewer, "post", f.post, "❤️", false);
    await set(client, f.viewer, "post", f.post, "😂", false);
    assertEquals((await people(client, f.viewer, f.post)).total_count, 2);
    await set(client, f.viewer, "post", f.post, "👩🏽‍🔬", false);
    assertEquals((await people(client, f.viewer, f.post)).total_count, 1);
  });
});

Deno.test("Explore reactors DB: bounded UUID pagination survives cursor actor removal and reaction additions", async () => {
  await withExploreDbTest("exploreReactorsDb", async (client) => {
    const f = await fixtures(client);
    const actors = Array.from({ length: 35 }, () => crypto.randomUUID()).sort();
    for (const [index, id] of actors.entries()) {
      await insertUser(client, id, `Page Reactor ${index}`);
      await set(client, id, "post", f.post, "😂");
    }
    await client.queryArray("SET LOCAL ROLE service_role");
    const first = await people(client, f.viewer, f.post);
    assertEquals(first.total_count, 35);
    assertEquals(first.reactors.map((p) => p.user_id), actors.slice(0, 32));
    assertEquals(first.next_cursor, actors[31]);
    await set(client, actors[31], "post", f.post, "😂", false);
    await set(client, actors[0], "post", f.post, "👍🏽");
    const next = await people(client, f.viewer, f.post, first.next_cursor);
    assertEquals(next.reactors.map((p) => p.user_id), actors.slice(32));
    assertEquals(next.next_cursor, null);
    assertEquals(next.total_count, 34);
    assertEquals(next.preview_names, first.preview_names);
  });
});

Deno.test("Explore reactors DB: unavailable post and caller boundaries deny identity reads", async () => {
  await withExploreDbTest("exploreReactorsDb", async (client) => {
    const f = await fixtures(client);
    for (const role of ["anon", "authenticated"]) {
      await client.queryArray("SAVEPOINT denial");
      await client.queryArray(`SET LOCAL ROLE ${role}`);
      await assertRejects(() => people(client, f.viewer, f.post));
      await client.queryArray("ROLLBACK TO SAVEPOINT denial");
    }
    for (
      const update of [
        "UPDATE public.explore_posts SET moderated_at=now() WHERE id=$1",
        "UPDATE public.explore_posts SET unshared_at=now() WHERE id=$1",
        "DELETE FROM public.explore_posts WHERE id=$1",
      ]
    ) {
      await client.queryArray("SAVEPOINT denial");
      await client.queryArray(update, [f.post]);
      await client.queryArray("SET LOCAL ROLE service_role");
      await assertRejects(() => people(client, f.viewer, f.post));
      await client.queryArray("ROLLBACK TO SAVEPOINT denial");
    }
    await client.queryArray(
      "INSERT INTO public.user_blocks(blocker_id,blocked_id) VALUES($1,$2)",
      [f.owner, f.viewer],
    );
    await client.queryArray("SET LOCAL ROLE service_role");
    await assertRejects(() => people(client, f.viewer, f.post));
  });
});
