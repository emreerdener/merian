import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type EdgeAuthenticator,
  jsonResponse,
  serveEdge,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { PUBLIC_SPECIES_SCHEMA_VERSION } from "../_shared/publicSpeciesProjection.ts";
import {
  fetchSpeciesDictionary,
  fetchSpeciesDictionaryCatalog,
  fetchSpeciesDictionaryOverview,
  parseSpeciesDictionaryRequest,
} from "../species-dictionary/db.ts";

export const viewerDictionaryHeaders = {
  "Cache-Control": "private, no-store",
  "Vary": "Authorization",
};

interface ViewerDictionaryDependencies {
  catalog: typeof fetchSpeciesDictionaryCatalog;
  overview: typeof fetchSpeciesDictionaryOverview;
  detail: typeof fetchSpeciesDictionary;
}
const liveDependencies: ViewerDictionaryDependencies = {
  catalog: fetchSpeciesDictionaryCatalog,
  overview: fetchSpeciesDictionaryOverview,
  detail: fetchSpeciesDictionary,
};

export async function handleViewerDictionary(
  req: Request,
  viewerId: string,
  admin: SupabaseClient,
  dependencies: ViewerDictionaryDependencies = liveDependencies,
): Promise<Response> {
  const body = await parseJsonBody(req, { limit: "standard" });
  if (body instanceof Response) return body;
  const parsed = parseSpeciesDictionaryRequest(body);
  if (parsed.error) {
    return jsonResponse(
      { error: parsed.error },
      parsed.status ?? 400,
      viewerDictionaryHeaders,
    );
  }
  if (parsed.mode === "catalog") {
    const page = await dependencies.catalog(
      {
        mode: "catalog",
        category: parsed.category,
        query: parsed.query,
        region: parsed.region,
        group: parsed.group,
        limit: parsed.limit ?? 40,
        cursor: parsed.cursor,
      },
      admin,
      viewerId,
    );
    return jsonResponse(
      {
        schema_version: PUBLIC_SPECIES_SCHEMA_VERSION,
        data: page.data,
        next_cursor: page.nextCursor
          ? {
            scientific_name: page.nextCursor.scientificName,
            species_id: page.nextCursor.speciesId,
            created_at: page.nextCursor.createdAt,
          }
          : null,
      },
      200,
      viewerDictionaryHeaders,
    );
  }
  const data = parsed.mode === "overview"
    ? await dependencies.overview(
      { mode: "overview", userRegion: parsed.userRegion },
      admin,
      viewerId,
    )
    : await dependencies.detail(parsed, admin, undefined, viewerId);
  return data
    ? jsonResponse(
      { schema_version: PUBLIC_SPECIES_SCHEMA_VERSION, data },
      200,
      viewerDictionaryHeaders,
    )
    : jsonResponse(
      { error: "Species not found" },
      404,
      viewerDictionaryHeaders,
    );
}

export function viewerDictionaryHttpHandler(
  req: Request,
  authenticate?: EdgeAuthenticator,
): Promise<Response> {
  return withEdgeHandler(
    req,
    (user, admin) => handleViewerDictionary(req, user.id, admin),
    {
      authenticate,
      responseHeaders: viewerDictionaryHeaders,
    },
  );
}

if (import.meta.main) serveEdge(viewerDictionaryHttpHandler);
