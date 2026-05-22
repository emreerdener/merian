import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizeExploreHashtag, withExplorePostHashtags } from "./explore.ts";

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

Deno.test("normalizeExploreHashtag accepts display hashtags for collection lookup", () => {
  assertEquals(normalizeExploreHashtag(" #CityBioBlitz ", "hashtag"), "citybioblitz");
});
