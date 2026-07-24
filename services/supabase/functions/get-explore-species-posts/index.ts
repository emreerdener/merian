import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";
import {
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostHashtags,
  withExplorePostMediaItems,
} from "../_shared/explore.ts";
import { fetchExploreSpeciesPosts } from "./db.ts";
import { parseExploreSpeciesPostsRequest } from "./request.ts";
import { prepareExploreSpeciesPostsPage } from "./response.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, {
      limit: "small",
      allowEmpty: true,
    });
    if (body instanceof Response) return body;

    const parsed = parseExploreSpeciesPostsRequest(body);

    const rows = await fetchExploreSpeciesPosts(
      user.id,
      parsed.speciesId,
      parsed.limit + 1,
      parsed.beforeImageQualityScore,
      parsed.beforeSharedAt,
      parsed.beforePostId,
      supabaseAdmin,
    );
    const page = prepareExploreSpeciesPostsPage(rows, parsed.limit);

    const data = await withExplorePostHashtags(
      await withExplorePostMediaItems(
        await withExploreAuthorUsernames(
          await withExploreAuthorProBadges(
            page.data,
            supabaseAdmin,
          ),
          supabaseAdmin,
        ),
        supabaseAdmin,
      ),
      supabaseAdmin,
    );

    return jsonResponse({ data, next_cursor: page.nextCursor }, 200);
  })
);
