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
import { processPendingStorageDeletions } from "../safe-delete/storageWorker.ts";

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
  const firstPass = await processAccountDeletionJobs(supabaseAdmin, {
    limit: parseLimit(body),
  });
  const storage = await processPendingStorageDeletions(
    supabaseAdmin,
    parseLimit(body),
  );
  // Completing the verification pass wakes its account job transactionally.
  // A second bounded claim can therefore remove Auth in this same reaper run.
  const finalPass = storage.completed > 0
    ? await processAccountDeletionJobs(supabaseAdmin, {
      limit: parseLimit(body),
    })
    : {
      claimed: 0,
      completed: 0,
      deferred: 0,
      waitingForStorage: 0,
      failures: [],
    };
  const failures = [...firstPass.failures, ...finalPass.failures];

  for (const failure of failures) {
    logStructuredError("account_deletion_reconciliation_deferred", {
      job_id: failure.jobId,
      stage: failure.stage,
      code: failure.code,
    });
  }
  for (const failure of storage.failures) {
    logStructuredError("account_storage_erasure_deferred", {
      deletion_id: failure.deletionId,
      code: failure.code,
    });
  }

  return jsonResponse(
    {
      success: true,
      account_claimed: firstPass.claimed + finalPass.claimed,
      account_completed: firstPass.completed + finalPass.completed,
      account_deferred: firstPass.deferred + finalPass.deferred,
      waiting_for_storage: firstPass.waitingForStorage +
        finalPass.waitingForStorage,
      storage_claimed: storage.claimed,
      storage_completed: storage.completed,
      storage_deferred: storage.deferred,
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
