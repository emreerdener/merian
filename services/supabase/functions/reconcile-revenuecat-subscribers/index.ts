import { logIdentitySafeError, serveEdge } from "../_shared/edgeHandler.ts";
import { publicErrorResponse, requestIdFor } from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { processRevenueCatReconciliations } from "./worker.ts";

serveEdge(async (request: Request): Promise<Response> => {
  const requestId = requestIdFor(request);
  if (request.method !== "POST") {
    return publicErrorResponse(
      request,
      405,
      "method_not_allowed",
      "Method not allowed.",
      { extraHeaders: { Allow: "POST" } },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const revenueCatApiKey = Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? "";
  const auth = authorizeServiceRoleRequestFromEnvironment(request);
  if (!auth.ok) {
    return publicErrorResponse(
      request,
      401,
      "unauthorized",
      "Unauthorized.",
    );
  }
  if (supabaseUrl.length === 0 || !revenueCatApiKey.startsWith("sk_")) {
    logIdentitySafeError("revenuecat_reconciliation_configuration_invalid", {
      stage: "configuration",
      code: "missing_configuration",
    });
    return publicErrorResponse(
      request,
      503,
      "service_unavailable",
      "The service is temporarily unavailable.",
    );
  }

  try {
    const supabaseAdmin = createServiceRoleClient(
      supabaseUrl,
      auth.serverApiKey,
    );
    const result = await processRevenueCatReconciliations(
      supabaseAdmin,
      revenueCatApiKey,
    );
    return new Response(JSON.stringify({ success: true, ...result }), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "X-Request-ID": requestId,
      },
    });
  } catch {
    logIdentitySafeError("revenuecat_reconciliation_request_failed", {
      stage: "worker",
      code: "operation_failed",
    });
    return publicErrorResponse(
      request,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
