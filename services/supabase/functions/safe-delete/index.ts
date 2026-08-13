import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { handleSafeDelete } from "./handler.ts";
import {
  ACCOUNT_DELETION_RECOVERY_MAX_BODY_BYTES,
  hashAccountDeletionCapability,
  parseSafeDeleteRequest,
  sha256Hex,
} from "./protocol.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed." }, 405, {
        Allow: "POST",
      });
    }

    const body = await parseJsonBody(req, {
      limit: "small",
      maxBytes: ACCOUNT_DELETION_RECOVERY_MAX_BODY_BYTES,
      allowEmpty: true,
    });
    if (body instanceof Response) return body;
    const parsed = parseSafeDeleteRequest(body);
    if ("status" in parsed) {
      return jsonResponse(
        { code: parsed.code, error: parsed.message },
        parsed.status,
      );
    }
    const recoverySecretHash = parsed.recoveryCapability === null
      ? null
      : parsed.protocolVersion === 2
      ? await hashAccountDeletionCapability(
        parsed.recoveryCapability,
        "v2_recovery",
      )
      : await sha256Hex(parsed.recoveryCapability);
    const v2Operation = parsed.protocolVersion === 2
      ? parsed.operation === "prepare"
        ? {
          protocolVersion: 2 as const,
          operation: "prepare" as const,
          acknowledgementSecretHash: await hashAccountDeletionCapability(
            parsed.acknowledgementCapability,
            "v2_acknowledgement",
          ),
        }
        : {
          protocolVersion: 2 as const,
          operation: "commit" as const,
        }
      : null;
    return await handleSafeDelete(
      user.id,
      supabaseAdmin,
      {},
      recoverySecretHash,
      v2Operation,
    );
  })
);
