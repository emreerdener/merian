import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  parseJsonBody,
  publicErrorResponse,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { backfillExploreAudioSpectrograms } from "./worker.ts";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serveEdge(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const auth = authorizeServiceRoleRequestFromEnvironment(request);
  if (!auth.ok) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let limit = 50;
  const body = await parseJsonBody(request, {
    limit: "small",
    allowEmpty: true,
  });
  if (body instanceof Response) return body;
  if (typeof body.limit === "number" && Number.isFinite(body.limit)) {
    limit = body.limit;
  }

  try {
    const supabaseAdmin = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      auth.serverApiKey,
    );
    const result = await backfillExploreAudioSpectrograms(
      supabaseAdmin,
      limit,
    );
    return jsonResponse({ success: true, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(JSON.stringify({
      event: "explore_audio_spectrogram_backfill_failed",
      error: message,
    }));
    return publicErrorResponse(
      request,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
