import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import {
  applyUserTombstone,
  deleteAuthProfile,
  queueStorageDeletion,
} from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    // 1. Delete the Auth profile first. This prevents token refresh and makes
    //    Auth-backed getUser checks fail. A previously issued signed access token
    //    can remain cryptographically valid until expiry, so database ACL/RLS and
    //    the tombstone step remain mandatory defenses during cleanup.
    //    If this throws, the subsequent steps are never reached.
    await deleteAuthProfile(user.id, supabaseAdmin);

    // Auth is now revoked. Any failure below leaves the account in a durable inconsistent
    // state: auth gone but data not anonymised. We log a structured alert so an operator
    // can manually run apply_user_tombstone for this user_id, then re-throw so the
    // caller receives a 500 (not a false-success 200).
    try {
      // 2. Anonymise all scan data via the tombstone RPC (rewrites user_id → 00000000-...).
      //    Auth refresh/getUser is unavailable at this point; database policies
      //    still protect against any not-yet-expired access token.
      await applyUserTombstone(user.id, supabaseAdmin);

      // 3. Queue R2 storage deletion — best-effort async cleanup, intentionally last.
      //    Auth and data anonymisation must succeed before we schedule media removal.
      await queueStorageDeletion(user.id, supabaseAdmin);
    } catch (postAuthError) {
      logStructuredError("safe_delete_partial_failure", {
        user_id: user.id,
        error: postAuthError instanceof Error
          ? postAuthError.message
          : String(postAuthError),
        state: "auth_deleted_data_not_anonymised",
        action_required:
          "Manually run apply_user_tombstone RPC for this user_id.",
      });
      throw postAuthError;
    }

    return jsonResponse(
      {
        success: true,
        message: "Account securely deleted and anonymized.",
      },
      200,
    );
  })
);
