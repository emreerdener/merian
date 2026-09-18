import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicHttpError } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { fetchReactions } from "./db.ts";
Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, client) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;
    const id = requireUuid(body.target_id, "target_id");
    if (
      body.target_kind !== "post" && body.target_kind !== "comment"
    ) throw publicHttpError(400, "Invalid target_kind.");
    const cursor = body.after_order ?? -1;
    if (
      typeof cursor !== "number" || !Number.isInteger(cursor) || cursor < -1 ||
      cursor > 10000
    ) throw publicHttpError(400, "Invalid after_order.");
    return jsonResponse(
      await fetchReactions(user.id, body.target_kind, id, cursor, client),
    );
  })
);
