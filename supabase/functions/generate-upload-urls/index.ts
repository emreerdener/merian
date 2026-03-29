// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { generateStagingUrls } from "./storage.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, _supabaseAdmin) => {
    let fileNames: string[];

    try {
      const body = await req.json();
      fileNames = body.fileNames;
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    // Limit uploads to 5 files per request to prevent R2 abuse
    if (
      !Array.isArray(fileNames) ||
      fileNames.length === 0 ||
      fileNames.length > 5
    ) {
      return jsonResponse(
        {
          error: "Bad Request: 'fileNames' must be an array of 1 to 5 values.",
        },
        400,
      );
    }

    const urls = await generateStagingUrls(user.id, fileNames);

    return jsonResponse({ success: true, urls }, 200);
  }),
);
