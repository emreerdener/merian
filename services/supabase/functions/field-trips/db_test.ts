import type { SupabaseClient } from "@supabase/supabase-js";
import { assertEquals } from "@std/assert";
import {
  applyFieldTripScanProgress,
  fetchFirstFieldTripAchievementProgress,
  hydrateFieldTripReferenceMedia,
  resetFieldTrip,
  stopFieldTrip,
} from "./db.ts";

const userId = "00000000-0000-0000-0000-000000000001";
const scanId = "00000000-0000-0000-0000-000000000002";

Deno.test("template reference hydration returns one candidate per provider in fallback order", async () => {
  const tableCalls: string[] = [];
  const supabase = {
    from: (table: string) => {
      tableCalls.push(table);
      const data = table === "species_dictionary"
        ? [{
          id: "species-bird",
          scientific_name: "Passer domesticus",
          common_names: { en: "House Sparrow" },
          wikipedia_url: "https://en.wikipedia.org/wiki/House_sparrow",
          reference_image_url:
            "https://upload.wikimedia.org/bird.jpg,https://api.gbif.org/media/bird.jpg",
        }]
        : [
          {
            id: "naturebook",
            species_id: "species-bird",
            url: "https://media.merian.app/bird.jpg",
            source: "merian",
            sort_order: 0,
          },
        ];
      const query = {
        select: () => query,
        in: () => query,
        order: () => query,
        limit: () => Promise.resolve({ data, error: null }),
      };
      return query;
    },
  } as unknown as SupabaseClient;

  const hydrated = await hydrateFieldTripReferenceMedia({
    slug: "backyard_safari",
    levels: [{
      items: [{ item_id: "bird", prompt: "Bird", is_completed: false }],
    }],
  }, supabase) as {
    levels: Array<{
      items: Array<{
        reference_species: {
          common_name: string;
          reference_images: Array<{ source: string; url: string }>;
        };
      }>;
    }>;
  };

  assertEquals(tableCalls, ["species_dictionary", "species_reference_images"]);
  assertEquals(
    hydrated.levels[0].items[0].reference_species.common_name,
    "House Sparrow",
  );
  assertEquals(
    hydrated.levels[0].items[0].reference_species.reference_images.map((
      image,
    ) => [
      image.source,
      image.url,
    ]),
    [
      ["merian", "https://media.merian.app/bird.jpg"],
      ["wikipedia", "https://upload.wikimedia.org/bird.jpg"],
      ["gbif", "https://api.gbif.org/media/bird.jpg"],
    ],
  );
});

Deno.test("template reference hydration fills missing active goals from bounded external sources", async () => {
  const fetchedScientificNames: string[] = [];
  const supabase = {
    from: (table: string) => {
      const data = table === "species_dictionary"
        ? [{
          id: "species-flower",
          scientific_name: "Taraxacum officinale",
          common_names: { en: "Common Dandelion" },
          wikipedia_url: "https://en.wikipedia.org/wiki/Taraxacum_officinale",
          reference_image_url: null,
        }]
        : [{
          id: "flower-image",
          species_id: "species-flower",
          url: "https://upload.wikimedia.org/dandelion.jpg",
          source: "wikipedia",
          sort_order: 0,
        }];
      const query = {
        select: () => query,
        in: () => query,
        order: () => query,
        limit: () => Promise.resolve({ data, error: null }),
      };
      return query;
    },
  } as unknown as SupabaseClient;

  const hydrated = await hydrateFieldTripReferenceMedia(
    {
      slug: "park_pollinators",
      levels: [
        {
          level_number: 1,
          items: [
            { item_id: "flower", prompt: "Flowering plant" },
            { item_id: "butterfly", prompt: "Butterfly or moth" },
          ],
        },
        {
          level_number: 2,
          items: [{ item_id: "bee", prompt: "Bee or wasp" }],
        },
      ],
    },
    supabase,
    (scientificName) => {
      fetchedScientificNames.push(scientificName);
      return Promise.resolve({
        wikipediaUrl: "https://en.wikipedia.org/wiki/Monarch_butterfly",
        wikiExtract: null,
        gbifKey: 5139790,
        referenceImageUrl:
          "https://upload.wikimedia.org/monarch.jpg,https://api.gbif.org/media/monarch.jpg",
        alternativeCommonNames: [],
        wikiTitle: "Monarch butterfly",
        gbifTaxonomy: null,
        gbifMatchStatus: "matched",
      });
    },
  ) as {
    levels: Array<{
      items: Array<{
        prompt: string;
        reference_species?: {
          common_name: string;
          reference_images: Array<{ source: string; url: string }>;
        };
      }>;
    }>;
  };

  assertEquals(fetchedScientificNames, ["Danaus plexippus"]);
  assertEquals(
    hydrated.levels[0].items.map((item) => [
      item.prompt,
      item.reference_species?.common_name,
      item.reference_species?.reference_images.map((image) => image.source),
    ]),
    [
      ["Flowering plant", "Common Dandelion", ["wikipedia"]],
      ["Butterfly or moth", "Monarch", ["wikipedia", "gbif"]],
    ],
  );
  assertEquals(hydrated.levels[1].items[0].reference_species, undefined);
});

Deno.test("template reference hydration remains available when the optional provider fallback fails", async () => {
  const tableCalls: string[] = [];
  const supabase = {
    from: (table: string) => {
      tableCalls.push(table);
      if (table !== "species_dictionary") {
        throw new Error(`Unexpected table ${table}`);
      }
      const query = {
        select: () => query,
        in: () => query,
        limit: () => Promise.resolve({ data: [], error: null }),
      };
      return query;
    },
  } as unknown as SupabaseClient;
  const template = {
    slug: "park_pollinators",
    levels: [{
      level_number: 1,
      items: [{ item_id: "butterfly", prompt: "Butterfly or moth" }],
    }],
  };

  const hydrated = await hydrateFieldTripReferenceMedia(
    template,
    supabase,
    () => Promise.reject(new Error("provider unavailable")),
  );

  assertEquals(hydrated, template);
  assertEquals(tableCalls, ["species_dictionary"]);
});

Deno.test("achievement progress scopes the service RPC to the verified user", async () => {
  let capturedName = "";
  let capturedArgs: Record<string, unknown> = {};
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      capturedName = name;
      capturedArgs = args;
      return Promise.resolve({
        data: {
          kind: "standard_outing",
          completed_at: "2026-07-18T14:00:00Z",
          template_slug: "backyard_safari",
          challenge_id: null,
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  const progress = await fetchFirstFieldTripAchievementProgress(
    userId,
    supabase,
  );

  assertEquals(capturedName, "get_first_field_trip_achievement_progress");
  assertEquals(capturedArgs, { target_user_id: userId });
  assertEquals(progress?.template_slug, "backyard_safari");
});

Deno.test("apply progress reports newly unlocked only for the completing mutation", async () => {
  const achievement = {
    kind: "seasonal_challenge" as const,
    completed_at: "2026-07-18T14:00:00Z",
    template_slug: null,
    challenge_id: "00000000-0000-0000-0000-000000000003",
  };
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      assertEquals(name, "apply_field_trip_scan_progress_atomic");
      assertEquals(args, {
        self_id: userId,
        target_scan_id: scanId,
        preferred_user_field_trip_id: null,
        preferred_item_id: null,
      });
      return Promise.resolve({
        data: {
          field_trip_updates: [{ is_complete: true }],
          challenge_updates: [],
          first_field_trip_achievement: achievement,
          first_field_trip_achievement_newly_unlocked: true,
        },
        error: null,
      });
    },
  } as unknown as SupabaseClient;

  const progress = await applyFieldTripScanProgress(
    userId,
    scanId,
    null,
    supabase,
  );

  assertEquals(progress.fieldTripUpdates, [{ is_complete: true }]);
  assertEquals(progress.challengeUpdates, []);
  assertEquals(progress.firstFieldTripAchievement, achievement);
  assertEquals(progress.firstFieldTripAchievementNewlyUnlocked, true);
});

Deno.test("stop scopes lifecycle RPCs to the caller and returns stopped detail", async () => {
  const userFieldTripId = "00000000-0000-0000-0000-000000000004";
  const templateId = "00000000-0000-0000-0000-000000000005";
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      switch (name) {
        case "stop_field_trip":
          return Promise.resolve({ data: templateId, error: null });
        case "get_field_trip_template_detail":
          return Promise.resolve({
            data: { template_id: templateId, active_progress: null },
            error: null,
          });
        case "get_stopped_field_trip_progress":
          return Promise.resolve({
            data: [{
              template_id: templateId,
              stopped_progress: {
                user_field_trip_id: userFieldTripId,
                stopped_at: "2026-07-19T15:00:00Z",
              },
              levels: [{ level_number: 1, items: [] }],
            }],
            error: null,
          });
        default:
          throw new Error(`Unexpected RPC ${name}`);
      }
    },
  } as unknown as SupabaseClient;

  const detail = await stopFieldTrip(userId, userFieldTripId, supabase) as {
    stopped_progress: { user_field_trip_id: string };
    levels: unknown[];
  };

  assertEquals(detail.stopped_progress.user_field_trip_id, userFieldTripId);
  assertEquals(detail.levels.length, 1);
  assertEquals(calls.find((call) => call.name === "stop_field_trip")?.args, {
    self_id: userId,
    target_user_field_trip_id: userFieldTripId,
  });
  assertEquals(
    calls.find((call) => call.name === "get_field_trip_template_detail")
      ?.args,
    {
      self_id: userId,
      target_template_id: templateId,
      target_slug: null,
    },
  );
});

Deno.test("reset scopes lifecycle RPCs to the caller and returns initial detail", async () => {
  const userFieldTripId = "00000000-0000-0000-0000-000000000006";
  const templateId = "00000000-0000-0000-0000-000000000007";
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const supabase = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      switch (name) {
        case "reset_field_trip":
          return Promise.resolve({ data: templateId, error: null });
        case "get_field_trip_template_detail":
          return Promise.resolve({
            data: {
              template_id: templateId,
              active_progress: null,
              levels: [{ level_number: 1, items: [] }],
            },
            error: null,
          });
        case "get_stopped_field_trip_progress":
          return Promise.resolve({ data: [], error: null });
        default:
          throw new Error(`Unexpected RPC ${name}`);
      }
    },
  } as unknown as SupabaseClient;

  const detail = await resetFieldTrip(userId, userFieldTripId, supabase) as {
    active_progress: null;
  };

  assertEquals(detail.active_progress, null);
  assertEquals(calls.find((call) => call.name === "reset_field_trip")?.args, {
    self_id: userId,
    target_user_field_trip_id: userFieldTripId,
  });
});
