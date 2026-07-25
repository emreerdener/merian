import "server-only";

import { createClient } from "@supabase/supabase-js";

type AdminSupabaseConfig = {
  url: string;
  key: string;
};

function getAdminSupabaseConfig(): AdminSupabaseConfig | null {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  return url && key ? { url, key } : null;
}

function createModernSecretKeyFetch(key: string): typeof fetch {
  return async (input, init) => {
    const headers = new Headers(init?.headers);

    if (headers.get("Authorization") === `Bearer ${key}`) {
      headers.delete("Authorization");
    }

    return fetch(input, { ...init, headers });
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
      fetch: config.key.startsWith("sb_secret_")
        ? createModernSecretKeyFetch(config.key)
        : undefined,
    },
  });
}
