import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { hasMutualBlock, requireUuid } from "../_shared/explore.ts";
import {
  canViewExploreAuthorProfile,
  fetchUserFollowState,
  setUserFollow,
} from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req, { limit: "small" });
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["author_user_id", "is_following"]);
    if (paramErr) return paramErr;

    const authorUserId = requireUuid(body.author_user_id, "author_user_id");
    if (typeof body.is_following !== "boolean") {
      return jsonResponse({ error: "is_following must be a boolean." }, 400);
    }

    if (authorUserId === user.id) {
      return jsonResponse({ error: "You cannot follow yourself." }, 400);
    }

    if (body.is_following) {
      if (await hasMutualBlock(user.id, authorUserId, supabaseAdmin)) {
        return jsonResponse({ error: "You cannot follow this author." }, 403);
      }

      const canViewProfile = await canViewExploreAuthorProfile(
        user.id,
        authorUserId,
        supabaseAdmin,
      );

      if (!canViewProfile) {
        return jsonResponse({ error: "Explore author profile not found" }, 404);
      }
    }

    await setUserFollow(
      user.id,
      authorUserId,
      body.is_following,
      supabaseAdmin,
    );
    const state = await fetchUserFollowState(
      user.id,
      authorUserId,
      supabaseAdmin,
    );

    return jsonResponse({
      success: true,
      ...state,
    });
  })
);
