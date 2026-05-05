// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { toggleExploreCommentReaction } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["comment_id", "emoji"]);
    if (paramErr) return paramErr;

    const commentId = requireUuid(body.comment_id, "comment_id");
    const emoji = body.emoji;

    if (typeof emoji !== "string" || emoji.trim() === "") {
      return jsonResponse({ error: "emoji must be a valid string." }, 400);
    }

    await toggleExploreCommentReaction(commentId, user.id, emoji, supabaseAdmin);

    return jsonResponse({
      success: true,
      comment_id: commentId,
      emoji: emoji,
    });
  }),
);
