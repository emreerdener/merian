import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const client = createClient("https://qlarqavoqhkuwzmevrmf.supabase.co", "anon-key", {
  global: { headers: { Authorization: "Bearer my-token" } },
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
});

const { data, error } = await client.auth.getUser();
console.log("Error:", error?.message);
