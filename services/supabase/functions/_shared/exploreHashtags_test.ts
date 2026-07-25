import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  normalizeExploreHashtag,
  withExplorePostHashtags,
  withExplorePostMediaItems,
} from "./explore.ts";

type HashtagQueryResult = {
  data?: Array<{ post_id: string; tag: string }>;
  error?: { message: string } | null;
};

function makeHashtagClient(result: HashtagQueryResult) {
  const calls = {
    table: "",
    selectedColumns: "",
    postIds: [] as string[],
    orderedColumn: "",
  };

  return {
    calls,
    client: {
      from: (table: string) => {
        calls.table = table;
        return {
          select: (columns: string) => {
            calls.selectedColumns = columns;
            return {
              in: (_column: string, postIds: string[]) => {
                calls.postIds = postIds;
                return {
                  order: (column: string) => {
                    calls.orderedColumn = column;
                    return Promise.resolve(result);
                  },
                };
              },
            };
          },
        };
      },
    },
  };
}

type MediaQueryResult = {
  data?: Array<{
    post_id: string;
    kind: "image" | "video";
    url: string;
    thumbnail_url: string | null;
    order_index: number;
    duration_seconds: number | null;
    has_audio: boolean;
  }>;
  error?: { message: string } | null;
};

function makeMediaClient(result: MediaQueryResult) {
  const calls = {
    table: "",
    selectedColumns: "",
    postIds: [] as string[],
    orderedColumn: "",
  };

  return {
    calls,
    client: {
      from: (table: string) => {
        calls.table = table;
        return {
          select: (columns: string) => {
            calls.selectedColumns = columns;
            return {
              in: (_column: string, postIds: string[]) => {
                calls.postIds = postIds;
                return {
                  order: (column: string) => {
                    calls.orderedColumn = column;
                    return Promise.resolve(result);
                  },
                };
              },
            };
          },
        };
      },
    },
  };
}

Deno.test("withExplorePostHashtags attaches sorted tags and empty arrays for feed rows", async () => {
  const firstPostId = "00000000-0000-0000-0000-000000000010";
  const secondPostId = "00000000-0000-0000-0000-000000000020";
  const { client, calls } = makeHashtagClient({
    data: [
      { post_id: firstPostId, tag: "citybioblitz" },
      { post_id: firstPostId, tag: "springcount" },
    ],
    error: null,
  });

  const rows = await withExplorePostHashtags(
    [
      { post_id: firstPostId, hero_image_url: "first.webp" },
      { post_id: secondPostId, hero_image_url: "second.webp" },
    ],
    // deno-lint-ignore no-explicit-any
    client as any,
  );

  assertEquals(rows, [
    {
      post_id: firstPostId,
      hero_image_url: "first.webp",
      hashtags: ["citybioblitz", "springcount"],
    },
    {
      post_id: secondPostId,
      hero_image_url: "second.webp",
      hashtags: [],
    },
  ]);
  assertEquals(calls.table, "explore_post_hashtags");
  assertEquals(calls.selectedColumns, "post_id,tag");
  assertEquals(calls.postIds, [firstPostId, secondPostId]);
  assertEquals(calls.orderedColumn, "tag");
});

Deno.test("withExplorePostHashtags skips the lookup when the post page is empty", async () => {
  const neverCalledClient = {
    from: (_table: string): never => {
      throw new Error("from() must not be called for an empty post page");
    },
  };

  const rows = await withExplorePostHashtags(
    [],
    // deno-lint-ignore no-explicit-any
    neverCalledClient as any,
  );

  assertEquals(rows, []);
});

Deno.test("withExplorePostHashtags surfaces lookup failures", async () => {
  const { client } = makeHashtagClient({
    data: [],
    error: { message: "tag edge table unavailable" },
  });

  await assertRejects(
    () =>
      withExplorePostHashtags(
        [{ post_id: crypto.randomUUID() }],
        // deno-lint-ignore no-explicit-any
        client as any,
      ),
    Error,
    "Failed to fetch Explore post hashtags",
  );
});

Deno.test("withExplorePostMediaItems attaches ordered media and empty arrays for missing rows", async () => {
  const firstPostId = "00000000-0000-0000-0000-000000000010";
  const secondPostId = "00000000-0000-0000-0000-000000000020";
  const { client, calls } = makeMediaClient({
    data: [
      {
        post_id: firstPostId,
        kind: "video",
        url: "https://cdn.example/video.mp4",
        thumbnail_url: "https://cdn.example/thumb.jpg",
        order_index: 0,
        duration_seconds: 4.2,
        has_audio: true,
      },
      {
        post_id: firstPostId,
        kind: "image",
        url: "https://cdn.example/still.jpg",
        thumbnail_url: "https://cdn.example/still.jpg",
        order_index: 1,
        duration_seconds: null,
        has_audio: false,
      },
    ],
    error: null,
  });

  const rows = await withExplorePostMediaItems(
    [
      { post_id: firstPostId, hero_image_url: "thumb.jpg" },
      { post_id: secondPostId, hero_image_url: "other.jpg" },
    ],
    // deno-lint-ignore no-explicit-any
    client as any,
  );

  assertEquals(rows[0].media_items, [
    {
      kind: "video",
      url: "https://cdn.example/video.mp4",
      thumbnail_url: "https://cdn.example/thumb.jpg",
      order_index: 0,
      duration_seconds: 4.2,
      has_audio: true,
    },
    {
      kind: "image",
      url: "https://cdn.example/still.jpg",
      thumbnail_url: "https://cdn.example/still.jpg",
      order_index: 1,
      duration_seconds: null,
      has_audio: false,
    },
  ]);
  assertEquals(rows[1].media_items, []);
  assertEquals(calls.table, "explore_post_media");
  assertEquals(
    calls.selectedColumns,
    "post_id,kind,url,thumbnail_url,order_index,duration_seconds,has_audio",
  );
  assertEquals(calls.postIds, [firstPostId, secondPostId]);
  assertEquals(calls.orderedColumn, "order_index");
});

Deno.test("normalizeExploreHashtag accepts display hashtags for collection lookup", () => {
  assertEquals(
    normalizeExploreHashtag(" #CityBioBlitz ", "hashtag"),
    "citybioblitz",
  );
});
