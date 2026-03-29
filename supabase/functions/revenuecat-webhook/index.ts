import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { jsonResponse, runBackground } from "../_shared/edgeHandler.ts";
import { timingSafeCompare } from "../_shared/security.ts";

import { ensureUserExists, updateUserTier } from "./db.ts";
import { migrateUserStorage } from "./storage.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

serve(async (req: Request) => {
  try {
    const WEBHOOK_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
    const authHeader = req.headers.get("Authorization") ?? "";

    if (
      !WEBHOOK_SECRET ||
      !timingSafeCompare(authHeader, `Bearer ${WEBHOOK_SECRET}`)
    ) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body = await req.json();
    const event = body.event;

    if (!event) {
      return jsonResponse({ error: "No event found." }, 400);
    }

    const eventType = event.type;
    const userId = event.app_user_id;

    if (!userId) {
      return jsonResponse({ error: "No app_user_id found." }, 400);
    }

    console.log(`Webhook received: ${eventType} for user ${userId}`);

    // Ensure user row exists before updating subscription tier
    await ensureUserExists(userId, supabaseAdmin);

    if (
      ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "NON_RENEWING_PURCHASE"].includes(eventType)
    ) {
      await updateUserTier(userId, "pro", supabaseAdmin);
      runBackground(migrateUserStorage(userId, "free", "pro", supabaseAdmin));
    } else if (["EXPIRATION"].includes(eventType)) {
      await updateUserTier(userId, "free", supabaseAdmin);
      runBackground(migrateUserStorage(userId, "pro", "free", supabaseAdmin));
    }

    return jsonResponse({ success: true }, 200);
  } catch (error: Error | unknown) {
    console.error("Webhook processing failed:", error);
    const msg = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: msg }, 500);
  }
});
