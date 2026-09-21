import { assertEquals } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { searchPage } from "./db.ts";

Deno.test("discovery enrichment preserves the RPC's visibility-filtered media", async () => {
  const viewer = "00000000-0000-4000-8000-000000000001";
  const author = "00000000-0000-4000-8000-000000000002";
  const post = "00000000-0000-4000-8000-000000000003";
  const media = [{
    kind: "video" as const,
    url: "https://example.invalid/healthy.mp4",
    thumbnail_url: "https://example.invalid/healthy.webp",
    order_index: 1,
    duration_seconds: 10,
    has_audio: false,
  }];
  const paths: string[] = [];
  const admin = createClient("https://example.invalid", "fixture-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input, init) => {
        const path =
          new URL(input instanceof Request ? input.url : String(input))
            .pathname;
        paths.push(path);
        if (path.endsWith("/rpc/search_species_discovery")) {
          const args = JSON.parse(String(init?.body));
          assertEquals(args.self_id, viewer);
          assertEquals(args.result_kind, "sightings");
          return Promise.resolve(Response.json({
            species: [],
            next_cursor: null,
            sightings: [{
              post_id: post,
              author_user_id: author,
              media_items: media,
            }],
          }));
        }
        if (path.endsWith("/users")) {
          return Promise.resolve(
            Response.json([{
              id: author,
              subscription_tier: "pro",
              public_username: "fixture_author",
            }]),
          );
        }
        if (path.endsWith("/explore_post_hashtags")) {
          return Promise.resolve(
            Response.json([{ post_id: post, tag: "birds" }]),
          );
        }
        throw new Error(`Unexpected unprojected retrieval: ${path}`);
      },
    },
  });
  const result = await searchPage(
    admin,
    viewer,
    { query: "red", group: "birds", media: "video", mode: "description" },
    "sightings",
    null,
  );
  assertEquals(result.sightings[0].media_items, media);
  assertEquals(result.sightings[0].author_username, "fixture_author");
  assertEquals(result.sightings[0].author_is_pro, true);
  assertEquals(result.sightings[0].hashtags, ["birds"]);
  assertEquals(
    paths.some((path) => path.endsWith("/explore_post_media")),
    false,
  );
});
