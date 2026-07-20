import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { PUBLIC_SPECIES_SCHEMA_VERSION } from "../_shared/publicSpeciesProjection.ts";
import { fetchExplorePostDetail } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["post_id"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");
    const data = await fetchExplorePostDetail(user.id, postId, supabaseAdmin);

    if (!data) {
      return jsonResponse({ error: "Explore post not found" }, 404);
    }

    return jsonResponse({
      schema_version: PUBLIC_SPECIES_SCHEMA_VERSION,
      data,
    }, 200);
  })
);
