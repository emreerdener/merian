import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { parseReactorsRequest } from "./types.ts";
import { fetchPostReactors } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, client) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;
    const { postId, afterUserId } = parseReactorsRequest(body);
    return jsonResponse(
      await fetchPostReactors(user.id, postId, afterUserId, client),
    );
  })
);
