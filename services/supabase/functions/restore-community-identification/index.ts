import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req, { limit: "small" });
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["identification_id"]);
    if (paramErr) return paramErr;

    const identificationId = requireUuid(
      body.identification_id,
      "identification_id",
    );

    const { data, error } = await supabaseAdmin.rpc(
      "restore_explore_community_identification",
      {
        self_id: user.id,
        target_identification_id: identificationId,
      },
    );

    if (error) {
      throw new Error(
        `Failed to restore community identification: ${error.message}`,
      );
    }

    return jsonResponse({ success: true, data }, 200);
  })
);
