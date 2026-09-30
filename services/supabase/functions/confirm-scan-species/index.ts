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
  requireParams,
} from "../_shared/http.ts";
import {
  fetchVerifiedLookalikeTaxon,
  type VerifiedLookalikeTaxon,
} from "../_shared/verifiedSpecies.ts";
import { isScientificName, parseReviewRequest } from "./contract.ts";
import { admitReview, applyReview, findReviewTarget } from "./db.ts";

export interface ReviewDependencies {
  find: typeof findReviewTarget;
  admit: typeof admitReview;
  verify: typeof fetchVerifiedLookalikeTaxon;
  apply: typeof applyReview;
}
const live: ReviewDependencies = {
  find: findReviewTarget,
  admit: admitReview,
  verify: fetchVerifiedLookalikeTaxon,
  apply: applyReview,
};
export async function handleSpeciesReview(
  req: Request,
  user: User,
  admin: SupabaseClient,
  dependencies: ReviewDependencies = live,
): Promise<Response> {
  if (req.method !== "POST") {
    throw publicHttpError(405, "Use POST for species review.");
  }
  const body = await parseJsonBody(req, { limit: "small" });
  if (body instanceof Response) return body;
  const missing = requireParams(body, [
    "scan_id",
    "expected_revision",
    "action",
  ]);
  if (missing) return missing;
  const request = parseReviewRequest(body);
  req.signal.throwIfAborted();
  const target = await dependencies.find(admin, user.id, request.scan_id);
  if (
    ![request.expected_revision, request.expected_revision + 1].includes(
      target.revision,
    )
  ) {
    throw publicHttpError(
      409,
      "This review changed. Refresh the observation before trying again.",
      "species_review_revision_conflict",
    );
  }
  let name = request.scientific_name;
  if (request.action === "confirm_primary") {
    if (
      target.primary.resolution !== "species" ||
      !isScientificName(target.primary.scientific_name)
    ) {
      throw publicHttpError(
        422,
        "The original answer does not resolve a verifiable species.",
        "species_not_verified",
      );
    }
    name = target.primary.scientific_name;
  }
  let taxon: VerifiedLookalikeTaxon | null = null;
  if (name !== null) {
    req.signal.throwIfAborted();
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
        "This selection could not be verified as a species.",
        "species_not_verified",
      );
    }
  }
  req.signal.throwIfAborted();
  const receipt = await dependencies.apply(
    admin,
    user.id,
    request,
    name,
    taxon,
  );
  return jsonResponse(receipt, 200, { "Cache-Control": "private, no-store" });
}
export function handleAuthenticatedSpeciesReview(
  req: Request,
  authenticate?: EdgeAuthenticator,
  dependencies = live,
): Promise<Response> {
  return withEdgeHandler(
    req,
    (user, admin) => handleSpeciesReview(req, user, admin, dependencies),
    {
      authenticate,
      responseHeaders: { "Cache-Control": "private, no-store" },
    },
  );
}
if (import.meta.main) serveEdge((req) => handleAuthenticatedSpeciesReview(req));
