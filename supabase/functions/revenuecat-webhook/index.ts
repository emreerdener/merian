import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

serve(async (req: Request) => {
  try {
    const WEBHOOK_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
    const authHeader = req.headers.get("Authorization");

    if (!WEBHOOK_SECRET || authHeader !== `Bearer ${WEBHOOK_SECRET}`) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const event = body.event;

    if (!event) {
      return new Response(JSON.stringify({ error: "No event found" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const eventType = event.type;
    const userId = event.app_user_id;

    if (!userId) {
      return new Response(JSON.stringify({ error: "No app_user_id found" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log(`Received Webhook: ${eventType} for User: ${userId}`);

    // Ensure user exists in our DB, upsert ghost if missing
    await supabaseAdmin
      .from("users")
      .upsert({ id: userId, subscription_tier: "free" }, { onConflict: "id", ignoreDuplicates: true });

    if (["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION"].includes(eventType)) {
      // 1. Upgrade user tier to 'pro'
      const { error: updateError } = await supabaseAdmin
        .from("users")
        .update({ subscription_tier: "pro" })
        .eq("id", userId);

      if (updateError) {
        throw new Error(`Failed to upgrade user tier: ${updateError.message}`);
      }

      // Phase 2: Decoupled S3 Migration
      // Deferring bulk R2 bucket copying from /free/ to /pro/ to a dedicated async pg_cron worker
      // to guarantee webhook completes well within the 10-second Deno Edge limit and avoids 504 RevenueCat Retry loops.
      console.log(`[Webhook] User ${userId} upgraded to Pro. S3 migration cleanly deferred to background pg_cron worker.`);
    } else if (["EXPIRATION"].includes(eventType)) {
      // Revert user tier strictly back to 'free'
      const { error: downgradeError } = await supabaseAdmin
        .from("users")
        .update({ subscription_tier: "free" })
        .eq("id", userId);

      if (downgradeError) {
        throw new Error(`Failed to downgrade user tier: ${downgradeError.message}`);
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: Error | unknown) {
    console.error("Webhook processing failed:", error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "Unknown error" }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    });
  }
});
