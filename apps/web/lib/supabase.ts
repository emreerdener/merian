import { createClient } from "@supabase/supabase-js";

type SupabaseConfig = {
  url: string;
  key: string;
};

function getSupabaseConfig(): SupabaseConfig | null {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY ??
    process.env.SUPABASE_ANON_KEY ??
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !key) {
    return null;
  }

  return { url, key };
}

function getServiceRoleSupabaseConfig(): SupabaseConfig | null {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return { url, key };
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

export function createServerSupabaseClient() {
  const config = getSupabaseConfig();

  if (!config) {
    return null;
  }

  const usesModernSecretKey = config.key.startsWith("sb_secret_");

  return createClient(config.url, config.key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
    global: {
      fetch: usesModernSecretKey
        ? createModernSecretKeyFetch(config.key)
        : undefined,
    },
  });
}

export function createServiceRoleSupabaseClient() {
  const config = getServiceRoleSupabaseConfig();
  if (!config) return null;

  const usesModernSecretKey = config.key.startsWith("sb_secret_");
  return createClient(config.url, config.key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
    global: {
      fetch: usesModernSecretKey
        ? createModernSecretKeyFetch(config.key)
        : undefined,
    },
  });
}
