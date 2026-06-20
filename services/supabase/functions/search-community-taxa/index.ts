// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { normalizeLimit } from "../_shared/explore.ts";
import { normalizeCommunitySearchQuery } from "../_shared/communityIdentification.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (_user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["query"]);
    if (paramErr) return paramErr;

    const query = normalizeCommunitySearchQuery(body.query);
    const limit = normalizeLimit(body.limit, 20, 50);

    const { data, error } = await supabaseAdmin.rpc(
      "search_community_taxa",
      {
        query_text: query,
        max_limit: limit,
      },
    );

    if (error) {
      throw new Error(`Failed to search community taxa: ${error.message}`);
    }

    return jsonResponse({ data: data ?? [] }, 200);
  })
);
