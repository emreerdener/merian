import { assertEquals } from "@std/assert";
import {
  insertExplorePost,
  insertScan,
  insertSpecies,
  insertUser,
  withExploreDbTest,
} from "./exploreDbTestHelpers.ts";

Deno.test("reported posts remain hidden across reads and moderation outcomes, only for their reporter", async () => {
  await withExploreDbTest("reportedPostVisibility", async (db) => {
    const owner = crypto.randomUUID(),
      viewer = crypto.randomUUID(),
      other = crypto.randomUUID();
    const species = crypto.randomUUID(),
      scan = crypto.randomUUID(),
      post = crypto.randomUUID();
    await insertUser(db, owner, "Report Owner");
    await insertUser(db, viewer, "Report Viewer");
    await insertUser(db, other, "Other Viewer");
    await insertSpecies(db, species, "Reportus testensis");
    await insertScan(db, {
      id: scan,
      userId: owner,
      speciesId: species,
      latitude: 1,
      longitude: 1,
      geoprivacy: "open",
      imageUrl: "https://example.com/reported.jpg",
    });
    await insertExplorePost(db, { id: post, userId: owner, scanId: scan });
    await db.queryArray(
      "INSERT INTO public.explore_post_likes(post_id,user_id) VALUES ($1,$2)",
      [post, viewer],
    );
    await db.queryArray(
      "INSERT INTO public.explore_post_comments(post_id,user_id,body) VALUES ($1,$2,'Test comment')",
      [post, other],
    );
    const comment = crypto.randomUUID(), reply = crypto.randomUUID();
    await db.queryArray(
      "INSERT INTO public.explore_post_comments(id,post_id,user_id,body) VALUES ($1,$2,$3,'Parent')",
      [comment, post, viewer],
    );
    await db.queryArray(
      "INSERT INTO public.explore_post_comments(id,post_id,user_id,body,parent_comment_id) VALUES ($1,$2,$3,'Reply',$4)",
      [reply, post, other, comment],
    );
    await db.queryArray(
      "SELECT set_config('request.jwt.claims', '{\"role\":\"service_role\"}', true)",
    );
    const notificationsBefore = await db.queryObject(
      "SELECT * FROM public.get_explore_notifications_with_reactions($1)",
      [viewer],
    );
    assertEquals(notificationsBefore.rows.length > 0, true);
    await db.queryArray(
      "INSERT INTO public.explore_post_reports(post_id,reporter_user_id,post_author_user_id,reason) VALUES ($1,$2,$3,'Other')",
      [post, viewer, owner],
    );
    await db.queryArray("SET LOCAL ROLE service_role");
    for (const status of ["PENDING_REVIEW", "DISMISSED", "ACTIONED"]) {
      await db.queryArray(
        "UPDATE public.explore_post_reports SET status=$1 WHERE post_id=$2",
        [status, post],
      );
      for (
        const query of [
          "SELECT post_id FROM public.explore_projected_post_cards($1)",
          "SELECT post_id FROM public.get_explore_feed($1)",
          "SELECT post_id FROM public.get_explore_feed_liked($1)",
          "SELECT post_id FROM public.get_explore_post($1,$2)",
          "SELECT post_id FROM public.get_explore_post_detail($1,$2)",
          "SELECT post_id FROM public.get_explore_map_posts($1,2,0,2,0,100)",
        ]
      ) {
        const result = await db.queryObject<{ post_id: string }>(
          query,
          query.includes("$2") ? [viewer, post] : [viewer],
        ).catch((error) => {
          throw new Error(`Visibility reader failed: ${query}`, {
            cause: error,
          });
        });
        assertEquals(
          result.rows.some((row) => row.post_id === post),
          false,
          `${status}: ${query}`,
        );
      }
      const replies = await db.queryObject(
        "SELECT * FROM public.get_explore_comment_replies($1,$2)",
        [viewer, comment],
      );
      assertEquals(replies.rows.length, 0);
      const comments = await db.queryObject(
        "SELECT * FROM public.get_explore_comments($1,$2)",
        [viewer, post],
      );
      assertEquals(comments.rows.length, 0);
      const visible = await db.queryObject(
        "SELECT post_id FROM public.get_explore_post($1,$2)",
        [other, post],
      );
      assertEquals(visible.rows.length, 1);
      const anonymous = await db.queryObject(
        "SELECT post_id FROM public.get_explore_post(NULL,$1)",
        [post],
      );
      assertEquals(anonymous.rows.length, 1);
    }
    const community = crypto.randomUUID();
    await db.queryArray(
      "INSERT INTO public.explore_community_requests(id,post_id,scan_id,requested_by) VALUES ($1,$2,$3,$4)",
      [community, post, scan, owner],
    );
    const before = await db.queryObject(
      "SELECT * FROM public.get_community_identification_detail($1,$2)",
      [other, community],
    );
    assertEquals(before.rows.length, 1);
    for (const status of ["PENDING_REVIEW", "DISMISSED", "ACTIONED"]) {
      await db.queryArray(
        "UPDATE public.explore_post_reports SET status=$1 WHERE post_id=$2",
        [status, post],
      );
      for (
        const name of [
          "get_community_identification_feed",
          "get_community_identification_activity",
        ]
      ) {
        const rows = await db.queryObject<{ post_id: string }>(
          `SELECT post_id FROM public.${name}($1)`,
          [viewer],
        );
        assertEquals(rows.rows.some((row) => row.post_id === post), false);
      }
      const communityDetail = await db.queryObject(
        "SELECT * FROM public.get_community_identification_detail($1,$2)",
        [viewer, community],
      );
      assertEquals(communityDetail.rows.length, 0);
    }
    // Both notification variants must hide the reported post.
    await db.queryArray(
      "SELECT set_config('request.jwt.claims', '{\"role\":\"service_role\"}', true)",
    );
    for (
      const name of [
        "get_explore_notifications",
        "get_explore_notifications_with_reactions",
      ]
    ) {
      const result = await db.queryObject<{ post_id: string }>(
        `SELECT post_id FROM public.${name}($1)`,
        [viewer],
      );
      assertEquals(result.rows.some((row) => row.post_id === post), false);
    }
  });
});

Deno.test("reported source media cannot return through promoted, reassigned or legacy reference images", async () => {
  await withExploreDbTest("reportedReferenceVisibility", async (db) => {
    const owner = crypto.randomUUID(),
      viewer = crypto.randomUUID(),
      other = crypto.randomUUID();
    const species = crypto.randomUUID(),
      scan = crypto.randomUUID(),
      post = crypto.randomUUID();
    const hidden = "https://example.com/reported-reference.jpg",
      allowed = "https://example.com/allowed-reference.jpg";
    await insertUser(db, owner, "Reference Owner");
    await insertUser(db, viewer, "Reference Viewer");
    await insertUser(db, other, "Reference Other");
    await insertSpecies(db, species, "Referencus testensis");
    await insertScan(db, {
      id: scan,
      userId: owner,
      speciesId: species,
      latitude: 1,
      longitude: 1,
      geoprivacy: "open",
      imageUrl: hidden,
    });
    await insertExplorePost(db, { id: post, userId: owner, scanId: scan });
    await db.queryArray(
      "INSERT INTO public.explore_post_reports(post_id,reporter_user_id,post_author_user_id,reason,status) VALUES ($1,$2,$3,'Other','DISMISSED')",
      [post, viewer, owner],
    );
    await db.queryArray(
      "INSERT INTO public.species_reference_images(species_id,url,source,sort_order) VALUES ($1,$2,'merian',0),($1,$3,'wikipedia',1)",
      [species, hidden, allowed],
    );
    await db.queryArray(
      `INSERT INTO public.species_reference_image_merian_sources(
      species_id,explore_post_id,scan_id,user_id,image_url,image_index,image_quality_score,author_attribution,source_shared_at,is_promoted)
      VALUES ($1,$2,$3,$4,$5,0,90,'Test author',now(),true)`,
      [species, post, scan, owner, hidden],
    );
    assertEquals(
      (await db.queryObject<{ url: string }>(
        "SELECT public.viewer_species_first_reference_image_url($1,$2,$3) AS url",
        [viewer, species, hidden],
      )).rows[0].url,
      allowed,
    );
    const reassignedScan = crypto.randomUUID(),
      reassignedPost = crypto.randomUUID();
    await insertScan(db, {
      id: reassignedScan,
      userId: other,
      speciesId: species,
      latitude: 1,
      longitude: 1,
      geoprivacy: "open",
      imageUrl: hidden,
    });
    await insertExplorePost(db, {
      id: reassignedPost,
      userId: other,
      scanId: reassignedScan,
    });
    await db.queryArray(
      "UPDATE public.species_reference_image_merian_sources SET explore_post_id=$1,scan_id=$2,user_id=$3 WHERE species_id=$4 AND image_url=$5",
      [reassignedPost, reassignedScan, other, species, hidden],
    );
    const relatedSpecies = crypto.randomUUID();
    await insertSpecies(db, relatedSpecies, "Relatedus testensis");
    await db.queryArray(
      "INSERT INTO public.species_lookalikes(species_id,lookalike_id) VALUES ($1,$2) ON CONFLICT DO NOTHING",
      [relatedSpecies, species],
    );
    await db.queryArray("SET LOCAL ROLE service_role");
    const result = await db.queryObject<{ url: string }>(
      "SELECT public.viewer_species_first_reference_image_url($1,$2,$3) AS url",
      [viewer, species, hidden],
    );
    assertEquals(result.rows[0].url, allowed);
    const nested = await db.queryObject<
      {
        items: Array<
          { species_id: string; reference_image_url: string | null }
        >;
      }
    >(
      "SELECT public.viewer_species_similar_species($1,$2) AS items",
      [viewer, relatedSpecies],
    );
    assertEquals(
      nested.rows[0].items.filter((item) => item.species_id === species).map((
        item,
      ) => item.reference_image_url),
      [
        allowed,
      ],
    );
    const legacy = await db.queryObject<{ url: string }>(
      "SELECT public.viewer_species_reference_image_urls($1,NULL,$2) AS url",
      [viewer, `${hidden}, ${allowed}`],
    );
    assertEquals(legacy.rows[0].url, allowed);
    const none = await db.queryObject<{ url: string | null }>(
      "SELECT public.viewer_species_first_reference_image_url($1,NULL,$2) AS url",
      [viewer, hidden],
    );
    assertEquals(none.rows[0].url, null);
    const otherLegacy = await db.queryObject<{ url: string }>(
      "SELECT public.viewer_species_first_reference_image_url($1,NULL,$2) AS url",
      [other, hidden],
    );
    assertEquals(otherLegacy.rows[0].url, hidden);
    await db.queryArray(
      "SELECT set_config('request.jwt.claims', '{\"role\":\"service_role\"}', true)",
    );
    const filtered = await db.queryObject<{ urls: string[] }>(
      "SELECT public.filter_reported_explore_media($1,$2::text[]) AS urls",
      [viewer, [hidden, allowed]],
    );
    assertEquals(filtered.rows[0].urls, [allowed]);
  });
});
