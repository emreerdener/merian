import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  makePublicDisplayNameResponse,
  normalizePublicDisplayName,
  publicDisplayNameValidationError,
} from "./displayName.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const paramErr = requireParams(parsedBody, ["display_name"]);
    if (paramErr) return paramErr;

    const displayName = normalizePublicDisplayName(parsedBody.display_name);
    const validationError = publicDisplayNameValidationError(displayName);
    if (validationError) {
      return jsonResponse(
        { error: validationError, display_name: displayName },
        400,
      );
    }

    const { data: profile, error: profileError } = await supabaseAdmin
      .from("users")
      .select("id")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      return jsonResponse({ error: "User profile not found." }, 404);
    }

    const { error: updateError } = await supabaseAdmin
      .from("users")
      .update({
        public_author_name: displayName,
        public_identity_source: "display_name",
      })
      .eq("id", user.id);

    if (updateError) {
      throw new Error(`Failed to update display name: ${updateError.message}`);
    }

    return jsonResponse(makePublicDisplayNameResponse(displayName), 200);
  })
);
