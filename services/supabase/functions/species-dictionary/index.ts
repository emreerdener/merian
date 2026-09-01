import type { SupabaseClient } from "@supabase/supabase-js";
import { corsHeaders, jsonResponse, parseJsonBody } from "../_shared/http.ts";
import {
  logStructuredError,
  serveEdge,
  withPublicEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { PUBLIC_SPECIES_SCHEMA_VERSION } from "../_shared/publicSpeciesProjection.ts";
import { createServiceRoleClientFromEnvironment } from "../_shared/serviceRoleClient.ts";
import {
  fetchSpeciesDictionary,
  fetchSpeciesDictionaryCatalog,
  fetchSpeciesDictionaryOverview,
  parseSpeciesDictionaryRequest,
} from "./db.ts";

const publicDictionaryCacheHeaders = {
  "Cache-Control":
    "public, max-age=300, s-maxage=86400, stale-while-revalidate=604800",
  "Vary": "Accept-Encoding",
};

const overviewDictionaryCacheHeaders = {
  "Cache-Control": "no-store",
  "Vary": "Accept-Encoding",
};

export interface SpeciesDictionaryHandlerDependencies {
  createServiceRoleClient: (supabaseUrl: string) => SupabaseClient;
}

const liveDependencies: SpeciesDictionaryHandlerDependencies = {
  createServiceRoleClient: createServiceRoleClientFromEnvironment,
};

export async function handleSpeciesDictionaryRequest(
  req: Request,
  dependencies: SpeciesDictionaryHandlerDependencies = liveDependencies,
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const parsedBody = await parseJsonBody(req, { limit: "standard" });
    if (parsedBody instanceof Response) return parsedBody;

    const parsedRequest = parseSpeciesDictionaryRequest(parsedBody);
    if (parsedRequest.error) {
      return jsonResponse(
        { error: parsedRequest.error },
        parsedRequest.status ?? 400,
      );
    }

    const supabaseAdmin = dependencies.createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
    );

    if (parsedRequest.mode === "catalog") {
      const catalog = await fetchSpeciesDictionaryCatalog(
        {
          mode: "catalog",
          category: parsedRequest.category,
          query: parsedRequest.query,
          region: parsedRequest.region,
          group: parsedRequest.group,
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
              created_at: catalog.nextCursor.createdAt,
            }
            : null,
        },
        200,
        publicDictionaryCacheHeaders,
      );
    }

    if (parsedRequest.mode === "overview") {
      const overview = await fetchSpeciesDictionaryOverview(
        {
          mode: "overview",
          userRegion: parsedRequest.userRegion,
        },
        supabaseAdmin,
      );

      return jsonResponse(
        {
          schema_version: PUBLIC_SPECIES_SCHEMA_VERSION,
          data: overview,
        },
        200,
        overviewDictionaryCacheHeaders,
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
}

export function createSpeciesDictionaryHttpHandler(
  dependencies: SpeciesDictionaryHandlerDependencies = liveDependencies,
): (req: Request) => Promise<Response> {
  return (req: Request) =>
    withPublicEdgeHandler(
      req,
      () => handleSpeciesDictionaryRequest(req, dependencies),
    );
}

if (import.meta.main) {
  serveEdge((req) => handleSpeciesDictionaryRequest(req));
}
