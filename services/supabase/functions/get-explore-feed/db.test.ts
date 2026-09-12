import { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals, assertThrows } from "@std/assert";
import { fetchExploreFeed } from "./db.ts";
import { normalizeExploreFeedFilter } from "../_shared/explore.ts";

Deno.test("Explore feed forwards advanced filters before pagination", async () => {
  let capturedName = "";
  let capturedArgs: Record<string, unknown> = {};
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      capturedName = name;
      capturedArgs = args;
      return Promise.resolve({ data: [], error: null });
    },
  } as unknown as SupabaseClient;

  await fetchExploreFeed(
    "00000000-0000-0000-0000-000000000001",
    20,
    "trending",
    {
      beforeSharedAt: "2026-07-01T00:00:00.000Z",
      beforePostId: "00000000-0000-0000-0000-000000000002",
      beforeRankingValue: 8,
    },
    { latitude: null, longitude: null },
    {
      speciesCategories: ["birds", "mammals"],
      mediaTypes: ["audio"],
      sharedSince: "2026-06-01T00:00:00.000Z",
      nearbyRadiusMiles: 50,
    },
    supabase,
  );

  assertEquals(capturedName, "get_explore_feed_trending");
  assertEquals(capturedArgs.requested_species_categories, [
    "birds",
    "mammals",
  ]);
  assertEquals(capturedArgs.requested_media_types, ["audio"]);
  assertEquals(capturedArgs.shared_since, "2026-06-01T00:00:00.000Z");
  assertEquals(capturedArgs.before_ranking_value, 8);
});

Deno.test("Explore nearby feed forwards the selected radius", async () => {
  let capturedArgs: Record<string, unknown> = {};
  const supabase = {
    rpc: (_name: string, args: Record<string, unknown>) => {
      capturedArgs = args;
      return Promise.resolve({ data: [], error: null });
    },
  } as unknown as SupabaseClient;

  await fetchExploreFeed(
    "00000000-0000-0000-0000-000000000001",
    20,
    "nearby",
    {
      beforeSharedAt: null,
      beforePostId: null,
      beforeRankingValue: null,
    },
    { latitude: 30.2672, longitude: -97.7431 },
    {
      speciesCategories: [],
      mediaTypes: [],
      sharedSince: null,
      nearbyRadiusMiles: 25,
    },
    supabase,
  );

  assertEquals(capturedArgs.nearby_radius_miles, 25);
  assertEquals(capturedArgs.viewer_latitude, 30.2672);
  assertEquals(capturedArgs.viewer_longitude, -97.7431);
});

Deno.test("Explore liked filter validates without changing the default", () => {
  assertEquals(normalizeExploreFeedFilter("liked"), "liked");
  assertEquals(normalizeExploreFeedFilter(undefined), "recent");
  assertThrows(() => normalizeExploreFeedFilter("likes"));
  assertThrows(() => normalizeExploreFeedFilter({ filter: "liked" }));
});

Deno.test("Explore liked feed forwards viewer, filters, and unranked cursor", async () => {
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      assertEquals(name, "get_explore_feed_liked");
      assertEquals(args, {
        self_id: "00000000-0000-4000-8000-000000000001",
        max_limit: 2,
        requested_species_categories: ["birds"],
        requested_media_types: ["audio"],
        shared_since: "2026-06-01T00:00:00.000Z",
        before_shared_at: "2026-07-01T00:00:00.000Z",
        before_post_id: "00000000-0000-4000-8000-000000000002",
      });
      return Promise.resolve({ data: [], error: null });
    },
  } as unknown as SupabaseClient;
  assertEquals(
    await fetchExploreFeed(
      "00000000-0000-4000-8000-000000000001",
      2,
      "liked",
      {
        beforeSharedAt: "2026-07-01T00:00:00.000Z",
        beforePostId: "00000000-0000-4000-8000-000000000002",
        beforeRankingValue: null,
      },
      { latitude: null, longitude: null },
      {
        speciesCategories: ["birds"],
        mediaTypes: ["audio"],
        sharedSince: "2026-06-01T00:00:00.000Z",
        nearbyRadiusMiles: 25,
      },
      supabase,
    ),
    [],
  );
});
