import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { handleAppleCredentialRegistration } from "./handler.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed." }, 405, {
        Allow: "POST",
      });
    }

    return await handleAppleCredentialRegistration(
      req,
      user.id,
      supabaseAdmin,
    );
  })
);
