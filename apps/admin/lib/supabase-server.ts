import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { publicSupabaseEnv } from "./env";

export async function createServerSupabaseClient() {
  const cookieStore = await cookies();
  const env = publicSupabaseEnv();
  return createServerClient(env.url, env.key, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll(values) {
        try {
          for (const cookie of values) cookieStore.set(cookie.name, cookie.value, cookie.options);
        } catch {
          // Server Components cannot write cookies; proxy.ts refreshes them.
        }
      },
    },
  });
}
