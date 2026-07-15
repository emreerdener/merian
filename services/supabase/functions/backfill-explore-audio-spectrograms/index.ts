import { createClient } from "@supabase/supabase-js";
import { corsHeaders, timingSafeCompare } from "../_shared/http.ts";
import { backfillExploreAudioSpectrograms } from "./worker.ts";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const providedAuth = request.headers.get("Authorization") ?? "";
  if (
    !serviceRoleKey ||
    !timingSafeCompare(providedAuth, `Bearer ${serviceRoleKey}`)
  ) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let limit = 50;
  try {
    const body = await request.json() as { limit?: unknown };
    if (typeof body.limit === "number" && Number.isFinite(body.limit)) {
      limit = body.limit;
    }
  } catch {
    // The default bounded batch is valid for an empty request body.
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceRoleKey,
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
    return jsonResponse({ error: message }, 500);
  }
});
