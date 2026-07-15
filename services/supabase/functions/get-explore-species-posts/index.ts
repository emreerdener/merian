import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  refreshExploreAuthorStateBestEffort,
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
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // The parser below reports the required species_id field.
    }

    const parsed = parseExploreSpeciesPostsRequest(body);

    await refreshExploreAuthorStateBestEffort(
      user.id,
      supabaseAdmin,
      "get-explore-species-posts",
    );

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
