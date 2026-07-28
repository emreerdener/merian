import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import { requestDwcaExportJob } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    if (user.is_anonymous === true) {
      return publicErrorResponse(
        req,
        403,
        "account_required",
        "A permanent account is required to request an export.",
      );
    }

    const requestBody = await parseJsonBody(req, { limit: "small" });
    if (requestBody instanceof Response) return requestBody;

    const { includePreciseCoordinates = false, exportScope = "personal" } =
      requestBody;
    const userId = user.id;

    if (typeof exportScope !== "string") {
      return publicErrorResponse(
        req,
        400,
        "invalid_export_scope",
        "exportScope must be a string.",
      );
    }
    if (exportScope !== "personal") {
      return publicErrorResponse(
        req,
        403,
        "global_export_forbidden",
        "Global exports require an internal administrative workflow.",
      );
    }

    if (typeof includePreciseCoordinates !== "boolean") {
      return publicErrorResponse(
        req,
        400,
        "invalid_coordinate_option",
        "includePreciseCoordinates must be a boolean.",
      );
    }

    const disposition = await requestDwcaExportJob(
      userId,
      exportScope,
      includePreciseCoordinates,
      supabaseAdmin,
    );

    if (disposition === "disabled") {
      return publicErrorResponse(
        req,
        403,
        "feature_unavailable",
        "Scan exports are not currently available.",
      );
    }
    if (disposition === "rate_limited") {
      return jsonResponse(
        {
          error: "Rate Limit Exceeded",
          message: "You can only request one DwC-A export every 24 hours.",
        },
        429,
      );
    }
    if (disposition === "already_pending") {
      return jsonResponse(
        {
          error: "Rate Limit Exceeded",
          message: "An export job is already pending for your account.",
        },
        429,
      );
    }

    return jsonResponse(
      { success: true, message: "Export job queued successfully." },
      200,
    );
  })
);
