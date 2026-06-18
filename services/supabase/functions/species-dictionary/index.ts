// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { requireAuth } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import { logStructuredError } from "../_shared/edgeHandler.ts";
import { PUBLIC_SPECIES_SCHEMA_VERSION } from "../_shared/publicSpeciesProjection.ts";
import {
  fetchSpeciesDictionary,
  fetchSpeciesDictionaryCatalog,
  fetchUserScannedSpeciesDictionaryTree,
  parseSpeciesDictionaryRequest,
} from "./db.ts";

const publicDictionaryCacheHeaders = {
  "Cache-Control":
    "public, max-age=300, s-maxage=86400, stale-while-revalidate=604800",
  "Vary": "Accept-Encoding",
};

const privateDictionaryCacheHeaders = {
  "Cache-Control": "private, no-store",
  "Vary": "Authorization, Accept-Encoding",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;

    const parsedRequest = parseSpeciesDictionaryRequest(parsedBody);
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    if (parsedRequest.mode === "catalog") {
      const catalog = await fetchSpeciesDictionaryCatalog(
        {
          mode: "catalog",
          query: parsedRequest.query,
          limit: parsedRequest.limit ?? 40,
          cursor: parsedRequest.cursor,
        },
        supabaseAdmin,
      );

      return jsonResponse(
        {
          schema_version: PUBLIC_SPECIES_SCHEMA_VERSION,
          data: catalog.data,
          next_cursor: catalog.nextCursor
            ? {
              scientific_name: catalog.nextCursor.scientificName,
              species_id: catalog.nextCursor.speciesId,
            }
            : null,
        },
        200,
        publicDictionaryCacheHeaders,
      );
    }

    if (parsedRequest.mode === "tree") {
      const { user, response } = await requireAuth(req, supabaseAdmin);
      if (response) return response;
      if (!user) return jsonResponse({ error: "Unauthorized" }, 401);

      const tree = await fetchUserScannedSpeciesDictionaryTree(
        user.id,
        supabaseAdmin,
      );

      return jsonResponse(
        {
          schema_version: PUBLIC_SPECIES_SCHEMA_VERSION,
          data: tree,
        },
        200,
        privateDictionaryCacheHeaders,
      );
    }

    if (!parsedRequest.speciesId && !parsedRequest.scientificName) {
      return jsonResponse(
        { error: parsedRequest.error },
        parsedRequest.status ?? 400,
      );
    }

    const data = await fetchSpeciesDictionary(parsedRequest, supabaseAdmin);
    if (!data) {
      return jsonResponse({ error: "Species not found" }, 404);
    }

    return jsonResponse(
      {
        schema_version: PUBLIC_SPECIES_SCHEMA_VERSION,
        data,
      },
      200,
      publicDictionaryCacheHeaders,
    );
  } catch (error) {
    logStructuredError("species_dictionary_fetch_failed", {
      error: error instanceof Error ? error.message : String(error),
    });
    return jsonResponse({ error: "Internal Server Error" }, 500);
  }
});
