// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  requireUuid,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
} from "../_shared/explore.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["request_id"]);
    if (paramErr) return paramErr;

    const requestId = requireUuid(body.request_id, "request_id");
    const { data, error } = await supabaseAdmin.rpc(
      "get_community_identification_detail",
      {
        self_id: user.id,
        target_request_id: requestId,
      },
    );

    if (error) {
      throw new Error(
        `Failed to fetch community identification detail: ${error.message}`,
      );
    }

    const row = Array.isArray(data) ? data[0] : null;
    if (!row) {
      return jsonResponse({ error: "Community request not found" }, 404);
    }

    const [withBadges] = await withExploreAuthorUsernames(
      await withExploreAuthorProBadges([row], supabaseAdmin),
      supabaseAdmin,
    );

    return jsonResponse({ data: withBadges }, 200);
  })
);
