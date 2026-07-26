import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { fetchOwnedExploreMediaIncidents } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method Not Allowed" }, 405);
    }

    try {
      const data = await fetchOwnedExploreMediaIncidents(
        user.id,
        supabaseAdmin,
      );
      return jsonResponse({ data }, 200);
    } catch (error) {
      logStructuredError("explore_media_incidents_fetch_failed", {
        user_id: user.id,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  })
);
