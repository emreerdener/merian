import { createClient } from "@supabase/supabase-js";

type PublicSupabaseConfig = {
  url: string;
  key: string;
};

function getPublicSupabaseConfig(): PublicSupabaseConfig | null {
  const url = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_ANON_KEY ??
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  return url && key ? { url, key } : null;
}

export function createPublicServerSupabaseClient() {
  const config = getPublicSupabaseConfig();
  if (!config) return null;

  return createClient(config.url, config.key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}
