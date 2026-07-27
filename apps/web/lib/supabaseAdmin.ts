import "server-only";

import { createClient } from "@supabase/supabase-js";
import { resolveServerApiKeySources } from "./serverApiKey";

type AdminSupabaseConfig = {
  url: string;
  key: string;
};

const SUPABASE_SERVER_REQUEST_TIMEOUT_MS = 30_000;

function getAdminSupabaseConfig(): AdminSupabaseConfig | null {
  const url = process.env.SUPABASE_URL?.trim();
  const resolution = resolveServerApiKeySources({
    explicitServerApiKey: process.env.SUPABASE_SERVER_API_KEY,
    platformSecretKeys: process.env.SUPABASE_SECRET_KEYS,
    legacyServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  });
  return url && resolution.ok ? { url, key: resolution.key } : null;
}

function createServerSupabaseFetch(key: string): typeof fetch {
  return async (input, init) => {
    const sourceHeaders = init?.headers ??
      (input instanceof Request ? input.headers : undefined);
    const headers = new Headers(sourceHeaders);

    if (
      key.startsWith("sb_secret_") &&
      headers.get("Authorization") === `Bearer ${key}`
    ) {
      headers.delete("Authorization");
    }

    const callerSignal = init?.signal ??
      (input instanceof Request ? input.signal : undefined);
    const deadlineSignal = AbortSignal.timeout(
      SUPABASE_SERVER_REQUEST_TIMEOUT_MS,
    );
    const signal = callerSignal
      ? AbortSignal.any([callerSignal, deadlineSignal])
      : deadlineSignal;
    return fetch(input, { ...init, headers, signal });
  };
}

export function createAdminSupabaseClient() {
  const config = getAdminSupabaseConfig();
  if (!config) return null;

  return createClient(config.url, config.key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
    global: {
      fetch: createServerSupabaseFetch(config.key),
    },
  });
}
