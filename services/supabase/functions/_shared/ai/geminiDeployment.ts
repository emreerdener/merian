import { GEMINI_DEPLOYMENT_IDENTITIES } from "../geminiDeploymentIdentity.ts";
import {
  type PublicEdgeHandler,
  withPublicEdgeHandler,
} from "../edgeHandler.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../serviceRoleAuth.ts";
/** Name is an entrypoint literal, never derived from a caller URL or header. */
export function serveGeminiEdge(
  name: keyof typeof GEMINI_DEPLOYMENT_IDENTITIES,
  handler: PublicEdgeHandler,
): void {
  Deno.serve(async (req: Request) => {
    const probe = req.method === "HEAD" &&
      req.headers.get("X-Merian-Release-Identity") === "1";
    const auth = probe ? authorizeServiceRoleRequestFromEnvironment(req) : null;
    const response = probe
      ? new Response(null, {
        status: auth && auth.ok ? 204 : 401,
      })
      : await withPublicEdgeHandler(req, handler);
    const headers = new Headers(response.headers);
    headers.set(
      "X-Merian-Gemini-Bundle-SHA256",
      GEMINI_DEPLOYMENT_IDENTITIES[name],
    );
    headers.set("X-Merian-Gemini-Contract", "generation3_v1");
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  });
}
