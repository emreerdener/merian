import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { normalizeLimit, requireUuid } from "../_shared/explore.ts";
import { normalizeCommunitySearchQuery } from "../_shared/communityIdentification.ts";
import { searchCommunityTaxa } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (_user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["query"]);
    if (paramErr) return paramErr;

    const query = normalizeCommunitySearchQuery(body.query);
    const limit = normalizeLimit(body.limit, 20, 50);
    const taxonomyVersionId = body.taxonomy_version_id == null
      ? null
      : requireUuid(body.taxonomy_version_id, "taxonomy_version_id");

    const data = await searchCommunityTaxa(
      query,
      limit,
      taxonomyVersionId,
      supabaseAdmin,
    );

    return jsonResponse({ data }, 200);
  })
);
