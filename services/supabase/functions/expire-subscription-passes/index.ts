import { createClient } from "@supabase/supabase-js";
import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  publicErrorResponse,
  timingSafeCompare,
} from "../_shared/http.ts";
import { processExpiredSubscriptionPasses } from "./worker.ts";

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

  const expectedAuth = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  const providedAuth = req.headers.get("Authorization") ?? "";

  if (!timingSafeCompare(providedAuth, expectedAuth)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);
    const result = await processExpiredSubscriptionPasses(supabaseAdmin);

    return jsonResponse({ success: true, ...result }, 200);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error(`Expire Subscription Passes Error: ${message}`);
    return publicErrorResponse(
      req,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
