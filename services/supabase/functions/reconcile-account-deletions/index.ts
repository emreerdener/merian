import { createClient } from "@supabase/supabase-js";
import {
  jsonResponse,
  logStructuredError,
  serveEdge,
} from "../_shared/edgeHandler.ts";
import {
  corsHeaders,
  parseJsonBody,
  timingSafeCompare,
} from "../_shared/http.ts";
import { processAccountDeletionJobs } from "../safe-delete/worker.ts";

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405, {
      Allow: "POST",
    });
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const providedAuth = req.headers.get("Authorization") ?? "";
  if (
    !serviceRoleKey ||
    !timingSafeCompare(providedAuth, `Bearer ${serviceRoleKey}`)
  ) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  const body = await parseJsonBody(req, {
    limit: "small",
    allowEmpty: true,
  });
  if (body instanceof Response) return body;

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    serviceRoleKey,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );
  const result = await processAccountDeletionJobs(supabaseAdmin, {
    limit: parseLimit(body),
  });

  for (const failure of result.failures) {
    logStructuredError("account_deletion_reconciliation_deferred", {
      job_id: failure.jobId,
      stage: failure.stage,
      code: failure.code,
    });
  }

  return jsonResponse(
    {
      success: true,
      claimed: result.claimed,
      completed: result.completed,
      deferred: result.deferred,
    },
    200,
    { "Cache-Control": "private, no-store" },
  );
});

function parseLimit(value: unknown): number {
  if (!value || typeof value !== "object" || Array.isArray(value)) return 25;
  const limit = (value as Record<string, unknown>).limit;
  return typeof limit === "number" && Number.isFinite(limit) && limit > 0
    ? Math.trunc(limit)
    : 25;
}
