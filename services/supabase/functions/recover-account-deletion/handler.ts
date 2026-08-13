import type { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse } from "../_shared/edgeHandler.ts";
import { parseJsonBody, publicErrorResponse } from "../_shared/http.ts";
import {
  AccountDeletionRecoveryError,
  recoverAccountDeletion,
  recoverAccountDeletionV2,
} from "../safe-delete/db.ts";
import {
  ACCOUNT_DELETION_RECOVERY_MAX_BODY_BYTES,
  hashAccountDeletionCapability,
  parseAccountDeletionRecoveryRequest,
  sha256Hex,
} from "../safe-delete/protocol.ts";

export interface AccountDeletionRecoveryDependencies {
  recover?: typeof recoverAccountDeletion;
  recoverV2?: typeof recoverAccountDeletionV2;
}

export async function handleAccountDeletionRecovery(
  req: Request,
  supabaseAdmin: SupabaseClient,
  dependencies: AccountDeletionRecoveryDependencies = {},
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") {
    return publicErrorResponse(
      req,
      405,
      "method_not_allowed",
      "Method not allowed.",
      { extraHeaders: { Allow: "POST" } },
    );
  }

  const body = await parseJsonBody(req, {
    limit: "small",
    maxBytes: ACCOUNT_DELETION_RECOVERY_MAX_BODY_BYTES,
  });
  if (body instanceof Response) return body;
  const parsed = parseAccountDeletionRecoveryRequest(body);
  if ("status" in parsed) {
    return publicErrorResponse(
      req,
      parsed.status,
      parsed.code,
      parsed.message,
    );
  }

  try {
    const capabilityHash = parsed.protocolVersion === 2
      ? await hashAccountDeletionCapability(
        parsed.capability,
        parsed.operation === "recover" ? "v2_recovery" : "v2_acknowledgement",
      )
      : await sha256Hex(parsed.capability);
    const receipt = parsed.protocolVersion === 2
      ? await (dependencies.recoverV2 ?? recoverAccountDeletionV2)(
        supabaseAdmin,
        capabilityHash,
        parsed.operation,
      )
      : await (dependencies.recover ?? recoverAccountDeletion)(
        supabaseAdmin,
        capabilityHash,
        parsed.operation === "acknowledge",
      );
    return jsonResponse(
      {
        success: true,
        status: receipt.status,
        ...(parsed.protocolVersion === 2 ? { protocol_version: 2 } : {}),
        manual_provider_revocation_required:
          receipt.manualProviderRevocationRequired,
        recovery_capability_expires_at: receipt.recoveryExpiresAt,
        recovery_acknowledged: receipt.recoveryAcknowledged,
      },
      200,
      { "Cache-Control": "private, no-store" },
    );
  } catch (error) {
    if (error instanceof AccountDeletionRecoveryError) {
      return publicErrorResponse(
        req,
        error.status,
        error.code,
        error.message,
      );
    }
    throw error;
  }
}
