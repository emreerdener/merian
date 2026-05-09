// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { generateStagingUrls, parseStagingUploadFiles } from "./storage.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, _supabaseAdmin) => {
    let body: unknown;

    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const parsed = parseStagingUploadFiles(body);
    if (parsed.error || !parsed.files) {
      return jsonResponse(
        { error: parsed.error ?? "Invalid upload manifest" },
        parsed.status ?? 400,
      );
    }

    const urls = await generateStagingUrls(user.id, parsed.files);

    return jsonResponse({ success: true, urls }, 200);
  })
);
