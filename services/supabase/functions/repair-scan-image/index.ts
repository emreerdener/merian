import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { accountDeletionIsActive } from "../_shared/accountDeletion.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  normalizeRestoredObjectKey,
  normalizeSourceUrl,
} from "./validation.ts";
import { inspectOwnedScanImage, repairOwnedScanImage } from "./worker.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    if (await accountDeletionIsActive(user.id, supabaseAdmin)) {
      return jsonResponse(
        {
          error: "Account deletion is already in progress.",
          code: "account_deletion_in_progress",
        },
        409,
      );
    }

    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;

    const paramError = requireParams(body, ["source_url"]);
    if (paramError) return paramError;

    const sourceUrl = normalizeSourceUrl(body.source_url);
    const restoredObjectKey = normalizeRestoredObjectKey(
      body.restored_object_key,
      user.id,
    );

    if (restoredObjectKey == null) {
      const status = await inspectOwnedScanImage(
        user.id,
        sourceUrl,
        supabaseAdmin,
      );
      return jsonResponse({ data: { status } }, 200);
    }

    const result = await repairOwnedScanImage(
      user.id,
      sourceUrl,
      restoredObjectKey,
      supabaseAdmin,
    );
    return jsonResponse({
      data: {
        status: result.status,
        replacement_url: result.replacementUrl,
        updated_scan_count: result.updatedScanCount,
        updated_post_media_count: result.updatedPostMediaCount,
      },
    }, 200);
  })
);
