import { assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { backfillExploreAudioSpectrograms } from "./worker.ts";

Deno.test("backfillExploreAudioSpectrograms updates post snapshots and normalized assets", async () => {
  const mediaId = "00000000-0000-0000-0000-000000000001";
  const postId = "00000000-0000-0000-0000-000000000002";
  const scanId = "00000000-0000-0000-0000-000000000003";
  const audioUrl = "https://media.merian.app/public_uploads/pro/user/clip.wav";
  const thumbnailUrl =
    "https://media.merian.app/public_uploads/pro/user/spectrogram.png";
  const updates: Array<{ table: string; values: Record<string, unknown> }> = [];

  const supabase = {
    from(table: string) {
      return {
        select() {
          const query = chainableQuery();
          query.limit = () =>
            Promise.resolve({
              data: [{
                id: mediaId,
                post_id: postId,
                url: audioUrl,
                thumbnail_url: "",
              }],
              error: null,
            });
          query.in = () =>
            Promise.resolve({
              data: [{ id: postId, scan_id: scanId }],
              error: null,
            });
          return query;
        },
        update(values: Record<string, unknown>) {
          updates.push({ table, values });
          return chainableQuery({ data: null, error: null });
        },
      };
    },
  } as unknown as SupabaseClient;

  const result = await backfillExploreAudioSpectrograms(
    supabase,
    10,
    () => Promise.resolve(thumbnailUrl),
  );

  assertEquals(result, {
    scanned_count: 1,
    generated_count: 1,
    unsupported_count: 0,
    failed_count: 0,
    errors: [],
  });
  assertEquals(updates, [
    { table: "explore_post_media", values: { thumbnail_url: thumbnailUrl } },
    { table: "scan_media_assets", values: { thumbnail_url: thumbnailUrl } },
  ]);
});

function chainableQuery(result?: unknown) {
  const query: Record<string, unknown> & {
    eq: () => typeof query;
    ilike: () => typeof query;
    or: () => typeof query;
    order: () => typeof query;
    limit: () => Promise<unknown>;
    in: () => Promise<unknown>;
    then?: (resolve: (value: unknown) => void) => void;
  } = {
    eq() {
      return query;
    },
    ilike() {
      return query;
    },
    or() {
      return query;
    },
    order() {
      return query;
    },
    limit: () => Promise.resolve(result),
    in: () => Promise.resolve(result),
  };
  if (result !== undefined) {
    query.then = (resolve) => resolve(result);
  }
  return query;
}
