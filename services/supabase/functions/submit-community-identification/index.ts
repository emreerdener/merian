import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import {
  normalizeCommunityBoolean,
  normalizeCommunityReasoning,
  normalizeDisagreementMode,
} from "../_shared/communityIdentification.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req, { limit: "standard" });
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["request_id", "taxon_id"]);
    if (paramErr) return paramErr;

    const requestId = requireUuid(body.request_id, "request_id");
    const taxonId = requireUuid(body.taxon_id, "taxon_id");
    const disagreementMode = normalizeDisagreementMode(body.disagreement_mode);
    const reasoning = normalizeCommunityReasoning(body.reasoning);
    const isGenusBestPossible = normalizeCommunityBoolean(
      body.is_genus_best_possible,
      "is_genus_best_possible",
    );

    const { data, error } = await supabaseAdmin.rpc(
      "submit_explore_community_identification",
      {
        self_id: user.id,
        target_request_id: requestId,
        target_taxon_node_id: taxonId,
        target_disagreement_mode: disagreementMode,
        target_reasoning: reasoning,
        target_is_genus_best_possible: isGenusBestPossible,
      },
    );

    if (error) {
      throw new Error(
        `Failed to submit community identification: ${error.message}`,
      );
    }

    return jsonResponse({ success: true, data }, 200);
  })
);
