// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { corsHeaders, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import { logStructuredError } from "../_shared/edgeHandler.ts";
import { PUBLIC_SPECIES_SCHEMA_VERSION } from "../_shared/publicSpeciesProjection.ts";
import { fetchSpeciesDictionary, parseSpeciesDictionaryRequest } from "./db.ts";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;

    const parsedRequest = parseSpeciesDictionaryRequest(parsedBody);
    if (!parsedRequest.speciesId && !parsedRequest.scientificName) {
      return jsonResponse(
        { error: parsedRequest.error },
        parsedRequest.status ?? 400,
      );
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const data = await fetchSpeciesDictionary(parsedRequest, supabaseAdmin);
    if (!data) {
      return jsonResponse({ error: "Species not found" }, 404);
    }

    return jsonResponse({
      schema_version: PUBLIC_SPECIES_SCHEMA_VERSION,
      data,
    }, 200);
  } catch (error) {
    logStructuredError("species_dictionary_fetch_failed", {
      error: error instanceof Error ? error.message : String(error),
    });
    return jsonResponse({ error: "Internal Server Error" }, 500);
  }
});
