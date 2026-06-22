import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  normalizePublicUsername,
  publicUsernameValidationError,
} from "../update-public-username/validation.ts";

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
      return jsonResponse({
        available: false,
        username,
        error: validationError,
      }, 200);
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

    return jsonResponse({
      available: !existingUser,
      username,
      error: existingUser ? "That username is already taken." : null,
    }, 200);
  })
);
