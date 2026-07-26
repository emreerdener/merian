import { createClient } from "@supabase/supabase-js";
import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  parseJsonBody,
  publicErrorResponse,
  timingSafeCompare,
} from "../_shared/http.ts";
import { parseDurableObjectKeys } from "./validation.ts";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const configuredSecret = Deno.env.get("R2_EVENT_WEBHOOK_SECRET") ?? "";
  const providedSecret = req.headers.get("X-Merian-R2-Event-Secret") ?? "";
  if (
    configuredSecret.length < 32 ||
    !timingSafeCompare(providedSecret, configuredSecret)
  ) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const body = await parseJsonBody(req, { limit: "standard" });
  if (body instanceof Response) return body;
  const keys = parseDurableObjectKeys(body.object_keys);
  if (!keys) {
    return jsonResponse({ error: "Invalid object_keys" }, 400);
  }

  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const { data, error } = await supabaseAdmin.rpc(
      "expedite_explore_media_health_checks",
      { p_object_keys: keys },
    );
    if (error) throw new Error(error.message);

    return jsonResponse({
      success: true,
      accepted_key_count: keys.length,
      matched_media_count: data ?? 0,
    });
  } catch (error) {
    console.error(JSON.stringify({
      event: "r2_media_event_ingest_failed",
      error: error instanceof Error ? error.message : String(error),
      key_count: keys.length,
      ts: new Date().toISOString(),
    }));
    return publicErrorResponse(
      req,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
