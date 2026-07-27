import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { jsonResponse } from "../_shared/edgeHttp.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";

serve((req: Request) => {
  try {
    const auth = authorizeServiceRoleRequestFromEnvironment(req);
    if (!auth.ok) {
      // DEBUG INJECTION START
      const token = req.headers.get("apikey")?.trim() ||
        req.headers.get("Authorization")?.trim() || "";

      const s = "SUPABASE_SECRET_KEYS";
      const a = "SUPABASE_SERVER_API_KEY";
      const rawEnv = Deno.env.get(s) ?? "";

      const debug = {
        hasServerKey: !!Deno.env.get(a),
        hasSecretKeys: !!rawEnv,
        secretKeysLength: rawEnv.length,
        secretKeysPrefix: rawEnv.substring(0, 10),
        secretKeysSuffix: rawEnv.substring(rawEnv.length - 5),
        tokenPrefix: token.substring(0, 10),
        tokenSuffix: token.substring(token.length - 5),
        tokenLength: token.length,
        authReason: (auth as { reason?: string }).reason,
      };
      // DEBUG INJECTION END
      return jsonResponse({ error: "Unauthorized", debug }, { status: 401 });
    }

    return jsonResponse({
      success: true,
      view: "coverage",
      coverage_targets: ["birds"],
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Internal Error" },
      { status: 500 },
    );
  }
});
