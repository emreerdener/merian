import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  makeHttpError,
  normalizeCommunityLocationSharing,
  normalizeCommunityNote,
} from "../_shared/communityIdentification.ts";
import { requireUuid } from "../_shared/explore.ts";
import { updateCommunityIdentificationRequest } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req, { limit: "standard" });
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["request_id", "location_sharing"]);
    if (paramErr) return paramErr;

    const requestId = requireUuid(body.request_id, "request_id");
    const note = normalizeCommunityNote(body.note);
    const locationSharing = normalizeCommunityLocationSharing(
      body.location_sharing,
    );

    if (!locationSharing) {
      throw makeHttpError(
        400,
        "location_sharing must be open, obscured, or private.",
      );
    }

    const data = await updateCommunityIdentificationRequest(
      requestId,
      user.id,
      note,
      locationSharing,
      supabaseAdmin,
    );

    return jsonResponse({ success: true, data }, 200);
  })
);
