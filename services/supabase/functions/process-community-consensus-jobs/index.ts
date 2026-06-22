import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { normalizeLimit } from "../_shared/explore.ts";
import {
  corsHeaders,
  jsonResponse,
  timingSafeCompare,
} from "../_shared/http.ts";

Deno.serve(async (req: Request) => {
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
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }

    const limit = normalizeLimit(body.limit, 25, 100);
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { data, error } = await supabaseAdmin.rpc(
      "process_community_consensus_jobs",
      { max_jobs: limit },
    );

    if (error) {
      throw new Error(
        `Failed to process community consensus jobs: ${error.message}`,
      );
    }

    return jsonResponse({ success: true, data: data ?? [] }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, 500);
  }
});
