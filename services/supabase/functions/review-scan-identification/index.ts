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
import { admitReview } from "../confirm-scan-species/db.ts";
import { isScientificName } from "../confirm-scan-species/contract.ts";
import { parseRequest } from "./contract.ts";
import { applyReview, findTarget } from "./db.ts";
const live = {
  find: findTarget,
  apply: applyReview,
  admit: admitReview,
  verify: fetchVerifiedLookalikeTaxon,
};
export async function handleReview(
  req: Request,
  user: User,
  admin: SupabaseClient,
  dependencies = live,
): Promise<Response> {
  if (req.method !== "POST") {
    throw publicHttpError(405, "Use POST for identification review.");
  }
  const body = await parseJsonBody(req, { limit: "small" });
  if (body instanceof Response) return body;
  const request = parseRequest(body);
  req.signal.throwIfAborted();
  const target = await dependencies.find(admin, user.id, request.scan_id);
  if (
    ![request.expected_revision, request.expected_revision + 1].includes(
      target.revision,
    )
  ) {
    throw publicHttpError(
      409,
      "This identification changed. Review the latest decision.",
      "identification_review_revision_conflict",
    );
  }
  if (
    (target.primary !== null) !==
      (request.expected_species_review_revision !== null)
  ) {
    throw publicHttpError(
      400,
      "Provide the matching species review revision.",
      "invalid_identification_review",
    );
  }
  let name = request.scientific_name;
  if (request.action === "confirm_primary") {
    if (
      (target.primary && target.primary.resolution !== "species") ||
      !isScientificName(target.name)
    ) {
      throw publicHttpError(
        422,
        "Choose a verifiable species.",
        "species_not_verified",
      );
    }
    name = target.name;
  }
  // A committed retry is validated by the atomic receipt before quota or GBIF work.
  // The RPC compares operation, base revision, action, name and species revision.
  if (target.revision === request.expected_revision + 1) {
    return jsonResponse(
      await dependencies.apply(admin, user.id, request, name, null),
      200,
      { "Cache-Control": "private, no-store" },
    );
  }
  let taxon = null;
  if (name !== null) {
    await dependencies.admit(admin, user.id);
    req.signal.throwIfAborted();
    try {
      taxon = await dependencies.verify(name, {}, fetch, req.signal);
    } catch {
      req.signal.throwIfAborted();
      throw publicHttpError(
        503,
        "Species verification is temporarily unavailable.",
        "species_resolution_unavailable",
      );
    }
    if (!taxon) {
      throw publicHttpError(
        422,
        "Choose a verifiable species.",
        "species_not_verified",
      );
    }
  }
  req.signal.throwIfAborted();
  return jsonResponse(
    await dependencies.apply(admin, user.id, request, name, taxon),
    200,
    { "Cache-Control": "private, no-store" },
  );
}
export function handleAuthenticatedReview(
  req: Request,
  authenticate?: EdgeAuthenticator,
  dependencies = live,
) {
  return withEdgeHandler(
    req,
    (user, admin) => handleReview(req, user, admin, dependencies),
    { authenticate, responseHeaders: { "Cache-Control": "private, no-store" } },
  );
}
if (import.meta.main) serveEdge((req) => handleAuthenticatedReview(req));
