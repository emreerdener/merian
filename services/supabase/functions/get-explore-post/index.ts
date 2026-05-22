// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import {
  refreshExploreAuthorStateBestEffort,
  requireUuid,
  withExploreAuthorProBadges,
  withExplorePostHashtags,
} from "../_shared/explore.ts";
import { fetchExplorePost } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["post_id"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");
    await refreshExploreAuthorStateBestEffort(
      user.id,
      supabaseAdmin,
      "get-explore-post",
    );

    let data;
    try {
      const fetchedPost = await fetchExplorePost(
        user.id,
        postId,
        supabaseAdmin,
      );
      data = fetchedPost
        ? (await withExplorePostHashtags(
          await withExploreAuthorProBadges([fetchedPost], supabaseAdmin),
          supabaseAdmin,
        ))[0]
        : null;
    } catch (error) {
      logStructuredError("explore_notification_open_fetch_failed", {
        user_id: user.id,
        post_id: postId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }

    if (!data) {
      return jsonResponse({ error: "Explore post not found" }, 404);
    }

    return jsonResponse({ data }, 200);
  })
);
