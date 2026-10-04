import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { handleScanDeletion } from "./handler.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const requestBody = await parseJsonBody(req, { limit: "small" });
    if (requestBody instanceof Response) return requestBody;

    const paramErr = requireParams(requestBody, ["scanId"]);
    if (paramErr) return paramErr;

    const { scanId } = requestBody;

    const UUID_RE =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (typeof scanId !== "string" || !UUID_RE.test(scanId)) {
      return jsonResponse({ error: "scanId must be a valid UUID." }, 400);
    }

    return await handleScanDeletion(scanId, user.id, supabaseAdmin);
  })
);
