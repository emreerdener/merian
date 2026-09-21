import type { SupabaseClient, User } from "@supabase/supabase-js";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicHttpError } from "../_shared/http.ts";
import { reserveAIProviderCall } from "../_shared/aiQuota.ts";
import { recordAIUsageBestEffort } from "../_shared/aiUsage.ts";
import { type Interpretation, parseSearchRequest } from "./contract.ts";
import { searchPage } from "./db.ts";
import { interpretSearch } from "./provider.ts";

export interface SearchDependencies {
  search: typeof searchPage;
  interpret: typeof interpretSearch;
  reserve: typeof reserveAIProviderCall;
  record: typeof recordAIUsageBestEffort;
}
const live: SearchDependencies = {
  search: searchPage,
  interpret: interpretSearch,
  reserve: reserveAIProviderCall,
  record: recordAIUsageBestEffort,
};
export async function handleDiscoverySearch(
  req: Request,
  user: User,
  admin: SupabaseClient,
  dependencies: SearchDependencies = live,
): Promise<Response> {
  if (req.method !== "POST") throw publicHttpError(405, "Use POST for search.");
  const body = await parseJsonBody(req, { limit: "small" });
  if (body instanceof Response) return body;
  const request = parseSearchRequest(body);
  let context = request.context;
  let interpretation: Interpretation | null = null;
  let page = null;
  // Common, scientific and alternative name matches do not require a model call.
  if (request.question && !context && request.question.length <= 240) {
    const nameContext = {
      query: request.question,
      group: null,
      media: null,
      mode: "name" as const,
    };
    const names = await dependencies.search(
      admin,
      user.id,
      nameContext,
      "species",
      null,
    );
    if (names.species.length) {
      context = nameContext;
      if (request.result_kind === "species") page = names;
    }
  }
  if (request.question && !page && (request.context || !context)) {
    const lease = await dependencies.reserve(req, admin, {
      userId: user.id,
      operation: "species_discovery_search",
      requestId: request.request_id,
    });
    let dispatched = false;
    try {
      req.signal.throwIfAborted();
      await lease.commit();
      dispatched = true;
      const generated = await dependencies.interpret(
        request.question,
        request.context,
        lease.reservation.model,
        req.signal,
      );
      interpretation = generated.interpretation;
      dependencies.record(admin, {
        operation: "species_discovery_search",
        model: lease.reservation.model,
        usage: generated.usage,
        userId: user.id,
        inputModality: "text",
        outcome: "success",
      });
      if (interpretation.status === "results") context = interpretation.context;
    } catch {
      if (dispatched) await lease.fail();
      else await lease.refund();
      throw publicHttpError(
        503,
        "Search is temporarily unavailable. Please try again.",
        "search_unavailable",
      );
    }
  }
  if (interpretation && interpretation.status !== "results") {
    return jsonResponse(
      {
        schema_version: 1,
        request_id: request.request_id,
        result_kind: request.result_kind,
        status: interpretation.status,
        message: interpretation.message,
        context: interpretation.status === "clarification"
          ? interpretation.context
          : request.context,
        species: [],
        sightings: [],
        next_cursor: null,
      },
      200,
      { "Cache-Control": "private, no-store" },
    );
  }
  if (!context) throw publicHttpError(400, "Enter a search.");
  page ??= await dependencies.search(
    admin,
    user.id,
    context,
    request.result_kind,
    request.cursor,
  );
  return jsonResponse(
    {
      schema_version: 1,
      request_id: request.request_id,
      result_kind: request.result_kind,
      status: "results",
      message: interpretation?.message || context.query ||
        "All species in this group",
      context,
      ...page,
    },
    200,
    { "Cache-Control": "private, no-store" },
  );
}
if (import.meta.main) {
  Deno.serve((req: Request) =>
    withEdgeHandler(
      req,
      (user, admin) => handleDiscoverySearch(req, user, admin),
      {
        responseHeaders: { "Cache-Control": "private, no-store" },
      },
    )
  );
}
