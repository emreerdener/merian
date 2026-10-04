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
import { parseAnalysisConfirmationRequest } from "../_shared/analysisHistory/confirmation.ts";
import { fetchVerifiedLookalikeTaxon } from "../_shared/verifiedSpecies.ts";
import { admitReview } from "../_shared/identify/speciesVerification.ts";
import { completeConfirmation, prepareConfirmation } from "./db.ts";

export interface ConfirmationDependencies {
  prepare: typeof prepareConfirmation;
  admit: typeof admitReview;
  verify: typeof fetchVerifiedLookalikeTaxon;
  complete: typeof completeConfirmation;
}
const live: ConfirmationDependencies = {
  prepare: prepareConfirmation,
  admit: admitReview,
  verify: fetchVerifiedLookalikeTaxon,
  complete: completeConfirmation,
};
const headers = { "Cache-Control": "private, no-store" };

export async function handleAnalysisConfirmation(
  req: Request,
  user: User,
  admin: SupabaseClient,
  dependencies: ConfirmationDependencies = live,
): Promise<Response> {
  if (req.method !== "POST") {
    throw publicHttpError(405, "Use POST for identification review.");
  }
  const body = await parseJsonBody(req, { limit: "small" });
  if (body instanceof Response) return body;
  let request;
  try {
    request = parseAnalysisConfirmationRequest(body);
  } catch {
    throw publicHttpError(
      400,
      "Invalid identification review.",
      "invalid_analysis_history",
    );
  }
  req.signal.throwIfAborted();
  const prepared = await dependencies.prepare(admin, user.id, request);
  if (prepared.status === "complete") {
    return jsonResponse(prepared.receipt, 200, headers);
  }
  req.signal.throwIfAborted();
  await dependencies.admit(admin, user.id);
  req.signal.throwIfAborted();
  let taxon;
  try {
    taxon = await dependencies.verify(
      prepared.scientific_name,
      {},
      fetch,
      req.signal,
    );
  } catch {
    req.signal.throwIfAborted();
    throw publicHttpError(
      503,
      "Species verification is temporarily unavailable.",
      "species_resolution_unavailable",
    );
  }
  req.signal.throwIfAborted();
  const receipt = await dependencies.complete(
    admin,
    user.id,
    request,
    prepared.scientific_name,
    taxon,
  );
  return jsonResponse(receipt, 200, headers);
}

export function handleAuthenticatedAnalysisConfirmation(
  req: Request,
  authenticate?: EdgeAuthenticator,
  dependencies = live,
): Promise<Response> {
  return withEdgeHandler(
    req,
    (user, admin) => handleAnalysisConfirmation(req, user, admin, dependencies),
    { authenticate, responseHeaders: headers },
  );
}
if (import.meta.main) {
  serveEdge((req) => handleAuthenticatedAnalysisConfirmation(req));
}
