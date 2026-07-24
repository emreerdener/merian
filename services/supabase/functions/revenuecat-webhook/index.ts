import { createClient } from "@supabase/supabase-js";
import { serveEdge } from "../_shared/edgeHandler.ts";
import { createRevenueCatWebhookHandler } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

const handler = createRevenueCatWebhookHandler({
  supabaseAdmin,
  config: {
    authorizationSecret: Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "",
    signingSecret: Deno.env.get("REVENUECAT_WEBHOOK_SIGNING_SECRET") ?? "",
    apiKey: Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? "",
  },
});

serveEdge(handler);
