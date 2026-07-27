import { serveEdge } from "../_shared/edgeHandler.ts";
import { createServiceRoleClientFromEnvironment } from "../_shared/serviceRoleClient.ts";
import { createRevenueCatWebhookHandler } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAdmin = createServiceRoleClientFromEnvironment(supabaseUrl);

const handler = createRevenueCatWebhookHandler({
  supabaseAdmin,
  config: {
    authorizationSecret: Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "",
    signingSecret: Deno.env.get("REVENUECAT_WEBHOOK_SIGNING_SECRET") ?? "",
    apiKey: Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? "",
  },
});

serveEdge(handler);
