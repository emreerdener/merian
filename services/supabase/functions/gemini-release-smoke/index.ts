import { serveGeminiEdge } from "../_shared/ai/geminiDeployment.ts";
import { GEMINI_DEPLOYMENT_IDENTITIES } from "../_shared/geminiDeploymentIdentity.ts";
import { geminiSmokeCatalog } from "../_shared/ai/geminiSmokeCatalog.ts";
import {
  type GeminiSmokeClaim,
  type GeminiSmokeRepository,
  runGeminiReleaseSmoke,
} from "../_shared/ai/geminiSmoke.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { jsonResponse, parseJsonBody } from "../_shared/http.ts";

export async function handleGeminiReleaseSmoke(
  req: Request,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }
  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) return jsonResponse({ error: "Unauthorized" }, 401);
  const body = await parseJsonBody<Record<string, unknown>>(req, {
    limit: "small",
  });
  if (body instanceof Response) return body;
  if (
    !body || Object.keys(body).sort().join(",") !== "case_id,release_id" ||
    typeof body.release_id !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      body.release_id,
    ) ||
    typeof body.case_id !== "string" ||
    !/^[a-z][a-z0-9_]{1,79}$/.test(body.case_id)
  ) return jsonResponse({ error: "Invalid request" }, 400);
  const client = createServiceRoleClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    auth.serverApiKey,
  );
  const catalog = await geminiSmokeCatalog();
  if (!catalog.has(body.case_id)) {
    return jsonResponse({ error: "Unknown smoke case" }, 400);
  }
  const { data: scope, error } = await client.rpc(
    "read_gemini_release_smoke_scope",
    {
      p_release: body.release_id,
      p_case: body.case_id,
      p_functions: GEMINI_DEPLOYMENT_IDENTITIES,
    },
  ).retry(false).abortSignal(AbortSignal.timeout(5000));
  if (error || typeof scope !== "string" || !/^[0-9a-f]{64}$/.test(scope)) {
    return jsonResponse({ error: "Release unavailable" }, 409);
  }
  async function advance(
    release: string,
    caseId: string,
    owner: string,
    action: string,
    receipt: unknown = null,
    valid = false,
  ) {
    const { data, error } = await client.rpc("advance_gemini_release_smoke", {
      p_release: release,
      p_case: caseId,
      p_owner: owner,
      p_action: action,
      p_receipt: receipt,
      p_valid_answer: valid,
    }).retry(false).abortSignal(AbortSignal.timeout(5000));
    if (error || typeof data !== "string") {
      throw new Error("gemini_smoke_transition_unavailable");
    }
    return data;
  }
  const repository: GeminiSmokeRepository = {
    async claim(release, caseId) {
      const { data, error } = await client.rpc("claim_gemini_release_smoke", {
        p_release: release,
        p_case: caseId,
        p_configuration_digest: scope,
      }).retry(false).abortSignal(AbortSignal.timeout(5000));
      if (error || !data || typeof data.state !== "string") {
        throw new Error("gemini_smoke_claim_unavailable");
      }
      return data as GeminiSmokeClaim;
    },
    async dispatch(r, c, o) {
      await advance(r, c, o, "dispatch");
    },
    async receipt(r, c, o, value) {
      await advance(r, c, o, "receipt", value);
    },
    async outcome(r, c, o, value, valid) {
      return await advance(r, c, o, "outcome", value, valid);
    },
    async uncertain(r, c, o) {
      await advance(r, c, o, "uncertain");
    },
  };
  try {
    return jsonResponse(
      await runGeminiReleaseSmoke(
        body.release_id,
        body.case_id,
        catalog,
        repository,
      ),
    );
  } catch {
    return jsonResponse({ error: "Release smoke unavailable" }, 409);
  }
}
if (import.meta.main) {
  serveGeminiEdge("gemini-release-smoke", handleGeminiReleaseSmoke);
}
