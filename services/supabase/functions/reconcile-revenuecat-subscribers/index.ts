import { createClient } from "@supabase/supabase-js";
import { serveEdge } from "../_shared/edgeHandler.ts";
import {
  publicErrorResponse,
  requestIdFor,
  timingSafeCompare,
} from "../_shared/http.ts";
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
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const revenueCatApiKey = Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? "";
  const providedAuthorization = request.headers.get("Authorization") ?? "";
  if (
    serviceRoleKey.length === 0 ||
    !timingSafeCompare(
      providedAuthorization,
      `Bearer ${serviceRoleKey}`,
    )
  ) {
    return publicErrorResponse(
      request,
      401,
      "unauthorized",
      "Unauthorized.",
    );
  }
  if (supabaseUrl.length === 0 || !revenueCatApiKey.startsWith("sk_")) {
    console.error(
      `[reconcile-revenuecat-subscribers] request_id=${requestId} required configuration is missing.`,
    );
    return publicErrorResponse(
      request,
      503,
      "service_unavailable",
      "The service is temporarily unavailable.",
    );
  }

  try {
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
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
  } catch (error) {
    console.error(
      `[reconcile-revenuecat-subscribers] request_id=${requestId} failed:`,
      error,
    );
    return publicErrorResponse(
      request,
      500,
      "internal_error",
      "The request could not be completed.",
    );
  }
});
