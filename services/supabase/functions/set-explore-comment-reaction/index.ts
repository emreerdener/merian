import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicHttpError } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { canonicalReactionEmoji } from "../_shared/exploreReactions.ts";
import { setReaction } from "./db.ts";
Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, client) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;
    const id = requireUuid(body.comment_id, "comment_id");
    const emoji = canonicalReactionEmoji(body.emoji);
    if (typeof body.selected !== "boolean") {
      throw publicHttpError(400, "selected must be a boolean.");
    }
    return jsonResponse(
      await setReaction(user.id, "comment", id, emoji, body.selected, client),
    );
  })
);
