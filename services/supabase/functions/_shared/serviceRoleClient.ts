import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { createDeadlineFetchTransport } from "./outbound.ts";
import {
  requireServerApiKey,
  requireServerApiKeyFromEnvironment,
} from "./serviceRoleAuth.ts";

const SUPABASE_SERVICE_REQUEST_TIMEOUT_MS = 30_000;

/**
 * Applies the API-key transport policy at the final fetch boundary.
 *
 * supabase-js currently uses its project key as a fallback Bearer token when
 * there is no user session. Current `sb_secret_...` credentials are API keys,
 * not JWTs, so the fetch boundary removes only that exact fallback credential.
 * Any different Authorization value (for example a real user access token) is
 * preserved.
 */
export function createServiceRoleFetchTransport(
  serverApiKey: string,
  fetchImplementation: typeof fetch = fetch,
): typeof fetch {
  requireServerApiKey({
    envServerApiKey: serverApiKey,
  });
  const deadlineTransport = createDeadlineFetchTransport(
    SUPABASE_SERVICE_REQUEST_TIMEOUT_MS,
    fetchImplementation,
  );

  return deadlineTransport;
}

/**
 * Creates a privileged client for PostgREST, Storage, Functions, Auth, and RPC.
 */
export function createServiceRoleClient(
  supabaseUrl: string,
  serverApiKey: string,
  fetchImplementation: typeof fetch = fetch,
): SupabaseClient {
  const validatedServerApiKey = requireServerApiKey({
    envServerApiKey: serverApiKey,
  });
  const transport = createServiceRoleFetchTransport(
    validatedServerApiKey,
    fetchImplementation,
  );

  return createClient(supabaseUrl, validatedServerApiKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
    global: {
      fetch: transport,
    },
  });
}

/**
 * Compatibility alias for callers that only use data APIs.
 */
export const createServiceRoleDataClient = createServiceRoleClient;

export function createServiceRoleClientFromEnvironment(
  supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "",
  fetchImplementation: typeof fetch = fetch,
): SupabaseClient {
  return createServiceRoleClient(
    supabaseUrl,
    requireServerApiKeyFromEnvironment(),
    fetchImplementation,
  );
}
