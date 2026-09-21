import type { SupabaseClient, User } from "@supabase/supabase-js";
import {
  type EdgeAuthenticator,
  serveEdge,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import {
  jsonResponse,
  parseJsonBody,
  publicHttpError,
} from "../_shared/http.ts";
import { fetchVerifiedLookalikeTaxon } from "../_shared/verifiedSpecies.ts";
import { admitResolution, findSpecies, persistSpecies } from "./db.ts";

export interface ResolutionDependencies {
  admit: typeof admitResolution;
  find: typeof findSpecies;
  verify: typeof fetchVerifiedLookalikeTaxon;
  persist: typeof persistSpecies;
}
const live: ResolutionDependencies = {
  admit: admitResolution,
  find: findSpecies,
  verify: fetchVerifiedLookalikeTaxon,
  persist: persistSpecies,
};

export async function handleResolution(
  req: Request,
  user: User,
  admin: SupabaseClient,
  dependencies: ResolutionDependencies = live,
): Promise<Response> {
  if (req.method !== "POST") {
    throw publicHttpError(405, "Use POST for species resolution.");
  }
  const body = await parseJsonBody(req, { limit: "small" });
  if (body instanceof Response) return body;
  if (
    typeof body.scientific_name !== "string" ||
    body.scientific_name.length > 160
  ) {
    throw publicHttpError(
      400,
      "Provide a scientific name of up to 160 characters.",
    );
  }
  const name = body.scientific_name.trim().replace(/\s+/g, " ");
  if (
    !name ||
    Array.from(name).some((character) =>
      character.charCodeAt(0) < 32 || character.charCodeAt(0) === 127
    )
  ) {
    throw publicHttpError(400, "Provide a scientific name.");
  }
  req.signal.throwIfAborted();
  await dependencies.admit(admin, user.id);
  let result = await dependencies.find(admin, name);
  if (!result) {
    let taxon;
    try {
      taxon = await dependencies.verify(name, {}, fetch, req.signal);
    } catch {
      req.signal.throwIfAborted();
      throw publicHttpError(
        503,
        "Species verification is temporarily unavailable. Please try again.",
        "species_resolution_unavailable",
      );
    }
    req.signal.throwIfAborted();
    if (!taxon) {
      throw publicHttpError(
        422,
        "This species could not be verified yet.",
        "species_not_verified",
      );
    }
    result = await dependencies.persist(admin, taxon);
  }
  req.signal.throwIfAborted();
  return jsonResponse(
    { schema_version: 1, requested_scientific_name: name, ...result },
    200,
    { "Cache-Control": "private, no-store" },
  );
}

export function handleAuthenticatedResolution(
  req: Request,
  authenticate?: EdgeAuthenticator,
  dependencies = live,
): Promise<Response> {
  return withEdgeHandler(
    req,
    (user, admin) => handleResolution(req, user, admin, dependencies),
    { authenticate },
  );
}

if (import.meta.main) {
  serveEdge((req) => handleAuthenticatedResolution(req));
}
