import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.2";
const client = createClient("https://project.supabase.co", "sb_secret_worker_aaaaaaaaaaaaaaaaaaaa", {
  global: {
    fetch: (url, init) => {
      console.log("url", url, "headers", init?.headers);
      return Promise.resolve(new Response());
    }
  }
});
client.functions.invoke("internal-worker");
