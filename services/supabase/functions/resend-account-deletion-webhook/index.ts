import { serveEdge } from "../_shared/edgeHandler.ts";
import { createServiceRoleClientFromEnvironment } from "../_shared/serviceRoleClient.ts";
import { createResendAccountDeletionWebhookHandler } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAdmin = createServiceRoleClientFromEnvironment(supabaseUrl);

serveEdge(createResendAccountDeletionWebhookHandler({
  supabaseAdmin,
  signingSecret: Deno.env.get("RESEND_WEBHOOK_SIGNING_SECRET") ?? "",
}));
