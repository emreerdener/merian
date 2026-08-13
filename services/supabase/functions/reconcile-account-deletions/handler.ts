import type { SupabaseClient } from "@supabase/supabase-js";
import { jsonResponse, logIdentitySafeError } from "../_shared/edgeHandler.ts";
import { corsHeaders, parseJsonBody } from "../_shared/http.ts";
import {
  authorizeServiceRoleRequestFromEnvironment,
  type ServiceRoleAuthResult,
} from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import { pruneAccountDeletionRecoveryPreparations } from "../safe-delete/db.ts";
import {
  processPendingStorageDeletions,
  type StorageDeletionWorkerResult,
} from "../safe-delete/storageWorker.ts";
import {
  type AccountDeletionWorkerResult,
  processAccountDeletionJobs,
} from "../safe-delete/worker.ts";

export interface ReconcileAccountDeletionsDependencies {
  authorize?: (request: Request) => ServiceRoleAuthResult;
  createClient?: (url: string, serverApiKey: string) => SupabaseClient;
  processAccounts?: typeof processAccountDeletionJobs;
  processStorage?: typeof processPendingStorageDeletions;
  prunePreparations?: typeof pruneAccountDeletionRecoveryPreparations;
  supabaseUrl?: () => string;
}

type ParsedRequest =
  | { kind: "dry_run" }
  | { kind: "work"; limit: number };

export async function handleReconcileAccountDeletions(
  request: Request,
  dependencies: ReconcileAccountDeletionsDependencies = {},
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405, {
      Allow: "POST",
    });
  }

  const auth = dependencies.authorize
    ? dependencies.authorize(request)
    : authorizeServiceRoleRequestFromEnvironment(request);
  if (!auth.ok) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  const body = await parseJsonBody(request, {
    limit: "small",
    allowEmpty: true,
  });
  if (body instanceof Response) return body;
  const parsed = parseRequest(body);
  if (parsed instanceof Response) return parsed;

  // This exact authenticated mode verifies the deployed handler and current
  // server-key transport without creating a client, claiming a deletion job,
  // touching storage, or pruning a preparation.
  if (parsed.kind === "dry_run") {
    return jsonResponse(
      { success: true, dry_run: true },
      200,
      { "Cache-Control": "private, no-store" },
    );
  }

  const supabaseAdmin = (dependencies.createClient ?? createServiceRoleClient)(
    (dependencies.supabaseUrl ?? (() => Deno.env.get("SUPABASE_URL") ?? ""))(),
    auth.serverApiKey,
  );
  const processAccounts = dependencies.processAccounts ??
    processAccountDeletionJobs;
  const processStorage = dependencies.processStorage ??
    processPendingStorageDeletions;
  const prunePreparations = dependencies.prunePreparations ??
    pruneAccountDeletionRecoveryPreparations;

  const firstPass = await processAccounts(supabaseAdmin, {
    limit: parsed.limit,
  });
  const storage = await processStorage(supabaseAdmin, parsed.limit);
  // Completing the verification pass wakes its account job transactionally.
  // A second bounded claim can therefore remove Auth in this same reaper run.
  const finalPass: AccountDeletionWorkerResult = storage.completed > 0
    ? await processAccounts(supabaseAdmin, { limit: parsed.limit })
    : emptyAccountDeletionResult();
  const preparationsPruned = await prunePreparations(
    supabaseAdmin,
    parsed.limit,
  );
  logFailures(firstPass, finalPass, storage);

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
      recovery_preparations_pruned: preparationsPruned,
    },
    200,
    { "Cache-Control": "private, no-store" },
  );
}

function parseRequest(value: unknown): ParsedRequest | Response {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    if (Object.hasOwn(record, "dry_run")) {
      if (Object.keys(record).length === 1 && record.dry_run === true) {
        return { kind: "dry_run" };
      }
      return jsonResponse(
        { error: "Invalid request." },
        400,
        { "Cache-Control": "private, no-store" },
      );
    }
  }
  return { kind: "work", limit: parseLimit(value) };
}

function parseLimit(value: unknown): number {
  if (!value || typeof value !== "object" || Array.isArray(value)) return 25;
  const limit = (value as Record<string, unknown>).limit;
  return typeof limit === "number" && Number.isFinite(limit) && limit > 0
    ? Math.trunc(limit)
    : 25;
}

function emptyAccountDeletionResult(): AccountDeletionWorkerResult {
  return {
    claimed: 0,
    completed: 0,
    deferred: 0,
    waitingForStorage: 0,
    failures: [],
  };
}

function logFailures(
  firstPass: AccountDeletionWorkerResult,
  finalPass: AccountDeletionWorkerResult,
  storage: StorageDeletionWorkerResult,
): void {
  for (const failure of [...firstPass.failures, ...finalPass.failures]) {
    logIdentitySafeError("account_deletion_reconciliation_deferred", {
      operation: "delete_account",
      stage: failure.stage,
      code: failure.code,
    });
  }
  for (const failure of storage.failures) {
    logIdentitySafeError("account_storage_erasure_deferred", {
      operation: "delete_account",
      stage: "storage",
      code: failure.code,
    });
  }
}
