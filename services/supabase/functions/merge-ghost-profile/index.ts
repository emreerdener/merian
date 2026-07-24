import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { syncPublicAuthorIdentity } from "../_shared/explore.ts";
import { publicErrorResponse } from "../_shared/http.ts";
import { readRequestJsonWithinBudget } from "../_shared/mediaBudgets.ts";
import {
  consumeGhostMergeHandoff,
  deleteMergedGhostAuthUser,
  GhostMergeDatabaseError,
  issueGhostMergeHandoff,
  recordGhostAuthCleanup,
} from "./db.ts";
import {
  generateHandoffSecret,
  GHOST_MERGE_MAX_BODY_BYTES,
  parseGhostMergeRequest,
  sha256Hex,
} from "./protocol.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed." }, 405);
    }

    const bodyResult = await readRequestJsonWithinBudget<unknown>(
      req,
      GHOST_MERGE_MAX_BODY_BYTES,
    );
    if (bodyResult.error || bodyResult.value === undefined) {
      return jsonResponse(
        {
          code: "invalid_request",
          error: bodyResult.error?.message ?? "Invalid JSON body.",
        },
        bodyResult.error?.status ?? 400,
      );
    }

    const request = parseGhostMergeRequest(bodyResult.value);
    if ("status" in request) {
      return jsonResponse(
        { code: request.code, error: request.message },
        request.status,
      );
    }

    try {
      switch (request.operation) {
        case "prepare": {
          if (user.is_anonymous !== true) {
            return jsonResponse(
              {
                code: "ghost_session_required",
                error: "A guest session is required to prepare an upgrade.",
              },
              403,
            );
          }

          const handoffSecret = generateHandoffSecret();
          const secretHash = await sha256Hex(handoffSecret);
          const handoff = await issueGhostMergeHandoff(
            req,
            secretHash,
            request.provider,
            request.providerSubject,
          );

          return jsonResponse(
            {
              success: true,
              handoff_id: handoff.handoffId,
              handoff_secret: handoffSecret,
              expires_at: handoff.expiresAt,
            },
            201,
            {
              "Cache-Control": "no-store",
              "Pragma": "no-cache",
            },
          );
        }

        case "complete": {
          if (user.is_anonymous === true) {
            return jsonResponse(
              {
                code: "permanent_session_required",
                error:
                  "A permanent account session is required to complete an upgrade.",
              },
              403,
            );
          }

          const secretHash = await sha256Hex(request.handoffSecret);
          const receipt = await consumeGhostMergeHandoff(
            req,
            request.handoffId,
            secretHash,
          );

          const cleanup = await deleteMergedGhostAuthUser(
            receipt.ghostUserId,
            supabaseAdmin,
          );
          if (!cleanup.succeeded) {
            await recordGhostAuthCleanup(
              receipt.handoffId,
              false,
              cleanup.errorCode,
              supabaseAdmin,
            );
            logStructuredError("ghost_profile_merge_auth_cleanup_pending", {
              handoffId: receipt.handoffId,
              ghostUserId: receipt.ghostUserId,
              targetUserId: receipt.targetUserId,
              errorCode: cleanup.errorCode,
            });
            return publicErrorResponse(
              req,
              503,
              "auth_cleanup_pending",
              "Account data was upgraded, but identity cleanup is still pending. Retrying is safe.",
            );
          }

          await recordGhostAuthCleanup(
            receipt.handoffId,
            true,
            null,
            supabaseAdmin,
          );

          return jsonResponse(
            {
              success: true,
              target_user_id: receipt.targetUserId,
              merged_at: receipt.mergedAt,
              already_merged: receipt.alreadyMerged,
              message: "Guest profile securely upgraded.",
            },
            200,
          );
        }

        case "refresh_identity": {
          if (user.is_anonymous === true) {
            return jsonResponse(
              {
                code: "permanent_session_required",
                error: "A permanent account session is required.",
              },
              403,
            );
          }

          await syncPublicAuthorIdentity(user.id, supabaseAdmin);
          return jsonResponse({ success: true }, 200);
        }
      }
    } catch (error) {
      if (error instanceof GhostMergeDatabaseError) {
        logStructuredError("ghost_profile_merge_rejected", {
          userId: user.id,
          operation: request.operation,
          code: error.code,
          status: error.status,
          internalMessage: error.internalMessage,
        });
        return publicErrorResponse(
          req,
          error.status,
          error.code,
          error.message,
        );
      }
      throw error;
    }
  })
);
