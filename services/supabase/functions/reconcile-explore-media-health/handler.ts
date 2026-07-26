import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  publicErrorResponse,
} from "../_shared/http.ts";
import {
  authorizeServiceRoleRequest,
  type ServiceRoleProbe,
} from "../_shared/serviceRoleAuth.ts";
import {
  reconcileExploreMediaHealth,
  type ReconcileExploreMediaHealthOptions,
  type ReconcileExploreMediaHealthResult,
} from "./worker.ts";

type Reconcile = (
  supabaseAdmin: SupabaseClient,
  options?: ReconcileExploreMediaHealthOptions,
) => Promise<ReconcileExploreMediaHealthResult>;

type CreateAdminClient = (
  supabaseUrl: string,
  token: string,
) => SupabaseClient;

export interface ReconcileExploreMediaHealthHandlerOptions {
  supabaseUrl: string;
  envServiceRoleKey: string;
  serviceRoleProbe?: ServiceRoleProbe;
  createAdminClient?: CreateAdminClient;
  reconcile?: Reconcile;
}

function boundedInteger(
  value: unknown,
  minimum: number,
  maximum: number,
): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return Math.min(Math.max(Math.trunc(value), minimum), maximum);
}

function defaultCreateAdminClient(
  supabaseUrl: string,
  token: string,
): SupabaseClient {
  return createClient(supabaseUrl, token, {
    global: {
      headers: {
        Authorization: `Bearer ${token}`,
        apikey: token,
      },
    },
  });
}

export function createReconcileExploreMediaHealthHandler(
  options: ReconcileExploreMediaHealthHandlerOptions,
): (req: Request) => Promise<Response> {
  const createAdminClient = options.createAdminClient ??
    defaultCreateAdminClient;
  const reconcile = options.reconcile ?? reconcileExploreMediaHealth;

  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method Not Allowed" }, 405);
    }

    const auth = await authorizeServiceRoleRequest(req, {
      supabaseUrl: options.supabaseUrl,
      envServiceRoleKey: options.envServiceRoleKey,
      probe: options.serviceRoleProbe,
    });
    if (!auth.ok || !auth.token) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body = await parseJsonBody(req, {
      limit: "small",
      allowEmpty: true,
    });
    if (body instanceof Response) return body;
    const payload = body && typeof body === "object" && !Array.isArray(body)
      ? body as Record<string, unknown>
      : {};

    try {
      const supabaseAdmin = createAdminClient(
        options.supabaseUrl,
        auth.token,
      );
      const result = await reconcile(supabaseAdmin, {
        limit: boundedInteger(payload.limit, 1, 500),
        leaseSeconds: boundedInteger(
          payload.leaseSeconds ?? payload.lease_seconds,
          30,
          600,
        ),
      });
      return jsonResponse({ success: true, ...result });
    } catch (error) {
      console.error(JSON.stringify({
        event: "explore_media_health_reconciliation_failed",
        error: error instanceof Error ? error.message : String(error),
        ts: new Date().toISOString(),
      }));
      return publicErrorResponse(
        req,
        500,
        "internal_error",
        "The request could not be completed.",
      );
    }
  };
}
