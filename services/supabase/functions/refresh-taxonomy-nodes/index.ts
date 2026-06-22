import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  corsHeaders,
  jsonResponse,
  timingSafeCompare,
} from "../_shared/http.ts";

function normalizeSourceRevision(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw new Error("source_revision must be a string.");
  }

  const trimmed = value.trim().replace(/\s+/g, "-");
  if (trimmed.length === 0) return null;
  if (trimmed.length > 120) {
    throw new Error("source_revision must be 120 characters or fewer.");
  }

  return trimmed;
}

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

    const sourceRevision = normalizeSourceRevision(body.source_revision);
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { data, error } = await supabaseAdmin.rpc(
      "refresh_taxonomy_nodes_from_species_dictionary",
      {
        target_source_revision: sourceRevision,
        activate_version: true,
      },
    );

    if (error) {
      throw new Error(`Failed to refresh taxonomy nodes: ${error.message}`);
    }

    return jsonResponse({ success: true, data }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, 500);
  }
});
