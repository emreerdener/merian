import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  normalizePublicUsername,
  publicUsernameValidationError,
} from "./validation.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["username"]);
    if (paramErr) return paramErr;

    const username = normalizePublicUsername(body.username);
    const validationError = publicUsernameValidationError(username);
    if (validationError) {
      return jsonResponse({ error: validationError, username }, 400);
    }

    const { data: existingUser, error: existingError } = await supabaseAdmin
      .from("users")
      .select("id")
      .eq("public_username", username)
      .neq("id", user.id)
      .maybeSingle();

    if (existingError) {
      throw new Error(
        `Failed to check username availability: ${existingError.message}`,
      );
    }
    if (existingUser) {
      return jsonResponse({
        error: "That username is already taken.",
        username,
      }, 409);
    }

    const { data: currentUser, error: currentUserError } = await supabaseAdmin
      .from("users")
      .select("public_identity_source")
      .eq("id", user.id)
      .single();

    if (currentUserError || !currentUser) {
      return jsonResponse({ error: "User profile not found." }, 404);
    }

    const updatePayload: Record<string, string> = {
      public_username: username,
    };
    if (currentUser.public_identity_source === "alias") {
      updatePayload.public_author_name = username;
    }

    const { error: updateError } = await supabaseAdmin
      .from("users")
      .update(updatePayload)
      .eq("id", user.id);

    if (updateError) {
      if (updateError.code === "23505") {
        return jsonResponse({
          error: "That username is already taken.",
          username,
        }, 409);
      }
      throw new Error(`Failed to update username: ${updateError.message}`);
    }

    return jsonResponse({ username }, 200);
  })
);
