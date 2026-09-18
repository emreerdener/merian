import type { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../_shared/http.ts";
import type { ExplorePostReactorsPage } from "./types.ts";

export async function fetchPostReactors(
  userId: string,
  postId: string,
  afterUserId: string | null,
  client: SupabaseClient,
): Promise<ExplorePostReactorsPage> {
  const { data, error } = await client.rpc("get_explore_post_reactors", {
    self_id: userId,
    target_post_id: postId,
    after_user_id: afterUserId,
  });
  if (error?.code === "42501") {
    throw publicHttpError(403, "This post is no longer available.");
  }
  if (error) throw new Error("Could not load post reactions.");
  return data as ExplorePostReactorsPage;
}
