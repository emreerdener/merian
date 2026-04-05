import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { jsonResponse, runBackground } from "../_shared/edgeHandler.ts";
import { timingSafeCompare } from "../_shared/http.ts";

import { ensureUserExists, updateUserTier } from "./db.ts";
import { migrateUserStorage } from "./storage.ts";
import { setTierCache } from "../_shared/tierCache.ts";

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

    // Validate that app_user_id is a UUID string. A falsy check alone is insufficient:
    // RevenueCat can send anonymous IDs like "$RCAnonymousID:xxx" for un-linked purchases,
    // which would pass a !userId check but fail UUID constraints in the DB layer, causing
    // confusing 500 errors instead of an early, descriptive 400.
    const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (typeof userId !== "string" || !UUID_REGEX.test(userId)) {
      console.warn(`[revenuecat-webhook] Skipping non-UUID app_user_id: ${typeof userId === "string" ? userId.slice(0, 40) : typeof userId}`);
      return jsonResponse({ error: "Invalid or missing app_user_id — expected a UUID." }, 400);
    }

    console.log(`Webhook received: ${eventType} for user ${userId}`);

    // Ensure user row exists before updating subscription tier
    await ensureUserExists(userId, supabaseAdmin);

    if (
      ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "NON_RENEWING_PURCHASE"].includes(eventType)
    ) {
      await updateUserTier(userId, "pro", supabaseAdmin);
      // Immediately update the in-process tier cache so the next enrich-scan or identify
      // call on this isolate uses gemini-2.5-pro without waiting for the 5-minute TTL to expire.
      setTierCache(userId, "pro");
      runBackground(migrateUserStorage(userId, "free", "pro", supabaseAdmin));
    } else if (["EXPIRATION"].includes(eventType)) {
      await updateUserTier(userId, "free", supabaseAdmin);
      setTierCache(userId, "free");
      runBackground(migrateUserStorage(userId, "pro", "free", supabaseAdmin));
    }

    return jsonResponse({ success: true }, 200);
  } catch (error: Error | unknown) {
    console.error("Webhook processing failed:", error);
    const msg = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: msg }, 500);
  }
});
