import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Creates a privileged client for PostgREST, Storage, Functions, and RPC calls.
 *
 * Do not use the returned client's Auth namespace. Current `sb_secret_...`
 * credentials are API keys rather than JWTs, so the explicit access-token
 * override below intentionally disables supabase-js's Auth-token transport.
 */
export function createServiceRoleDataClient(
  supabaseUrl: string,
  serverApiKey: string,
  fetchImplementation: typeof fetch = fetch,
): SupabaseClient {
  return createClient(supabaseUrl, serverApiKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
    global: {
      fetch: fetchImplementation,
    },
    // supabase-js uses its key as a fallback Bearer token when there is no
    // session. Current secret keys are intentionally non-JWT credentials and
    // belong only in `apikey`, so an explicit empty access token disables that
    // fallback while leaving legacy service-role JWT behavior unchanged.
    ...(serverApiKey.startsWith("sb_secret_")
      ? { accessToken: () => Promise.resolve("") }
      : {}),
  });
}
