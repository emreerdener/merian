// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { normalizeLimit, requireUuid } from "../_shared/explore.ts";
import { fetchExploreAuthorProfile } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["author_user_id"]);
    if (paramErr) return paramErr;

    const authorUserId = requireUuid(body.author_user_id, "author_user_id");
    const previewLimit = normalizeLimit(body.preview_limit, 9, 30);
    const data = await fetchExploreAuthorProfile(
      user.id,
      authorUserId,
      previewLimit,
      supabaseAdmin,
    );

    if (!data) {
      return jsonResponse({ error: "Explore author profile not found" }, 404);
    }

    return jsonResponse({ data }, 200);
  })
);
