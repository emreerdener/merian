"use client";

import { createBrowserClient } from "@supabase/ssr";
import { publicSupabaseEnv } from "./env";

let browserClient: ReturnType<typeof createBrowserClient> | undefined;

export function createBrowserSupabaseClient() {
  const env = publicSupabaseEnv();
  browserClient ??= createBrowserClient(env.url, env.key);
  return browserClient;
}
