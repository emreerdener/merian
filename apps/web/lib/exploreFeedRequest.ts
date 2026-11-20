type FeedResult<Row> = {
  data: Row[] | null;
  error: { code?: string } | null;
};

type FeedRpc =
  | "get_public_web_explore_posts_page"
  | "get_public_web_explore_posts";

/** Compatibility is limited to the first page and the existing public projection. */
export async function requestExploreFeedRows<Row>(
  rpc: (
    name: FeedRpc,
    args: Record<string, string | number | null>,
  ) => PromiseLike<FeedResult<Row>>,
  cursor: { sharedAt: string; postId: string } | null,
): Promise<Row[]> {
  let result = await rpc("get_public_web_explore_posts_page", {
    p_max_limit: 48,
    p_before_shared_at: cursor?.sharedAt ?? null,
    p_before_post_id: cursor?.postId ?? null,
  });
  // PGRST202 means this exact RPC signature is absent from the schema cache.
  // Never bypass permission failures, network failures, or a continuation cursor.
  if (!cursor && result.error?.code === "PGRST202") {
    result = await rpc("get_public_web_explore_posts", {
      p_target_post_id: null,
      p_max_limit: 48,
    });
    if (result.error || !Array.isArray(result.data)) {
      throw new Error("Explore unavailable");
    }
    // The legacy RPC has no lookahead/cursor support. Do not invent pagination.
    return result.data.slice(0, 48);
  }
  if (result.error || !Array.isArray(result.data)) {
    throw new Error("Explore unavailable");
  }
  return result.data;
}
