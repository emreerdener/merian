import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { getR2Config, copyR2Object, deleteR2Object } from "../_shared/aws.ts";
import { jsonResponse } from "../_shared/edgeHandler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

async function migrateUserStorage(userId: string, sourcePrefix: string, targetPrefix: string) {
  try {

    let totalMigrated = 0;
    let hasMore = true;
    let start = 0;
    const pageSize = 1000;

    while (hasMore) {
      const { data: scans, error: scansError } = await supabaseAdmin
        .from("scans")
        .select("id, image_storage_urls")
        .eq("user_id", userId)
        .order("id", { ascending: true })
        .range(start, start + pageSize - 1);

      if (scansError) throw scansError;

      if (!scans || scans.length === 0) {
        hasMore = false;
        break;
      }

      const BATCH_SIZE = 50;
      for (let i = 0; i < scans.length; i += BATCH_SIZE) {
        const chunk = scans.slice(i, i + BATCH_SIZE);
        
        await Promise.allSettled(chunk.map(async (scan) => {
          if (!scan.image_storage_urls || scan.image_storage_urls.length === 0) return;

          let migrated = false;

          const urlPromises = scan.image_storage_urls.map(async (urlStr: string) => {
            if (urlStr.includes(`public_uploads/${sourcePrefix}/`)) {
              const parsedUrl = new URL(urlStr);
              const pathParts = parsedUrl.pathname.split("/");
              const fileName = pathParts.pop();
              const originalUserId = pathParts.pop();

              // CRITICAL SEC FIX: Prevent malicious actors from submitting spoofed payloads 
              // that overwrite or delete adjacent user's private captures in R2 via arbitrary URLs
              if (originalUserId !== userId) {
                  console.warn(`SECURITY VIOLATION (IDOR): Webhook user ${userId} attempted to migrate assets belonging to ${originalUserId}`);
                  return urlStr;
              }

              const sourceKey = `public_uploads/${sourcePrefix}/${originalUserId}/${fileName}`;
              const targetKey = `public_uploads/${targetPrefix}/${userId}/${fileName}`;

              const r2Config = getR2Config();
              const copyResponse = await copyR2Object(sourceKey, targetKey, r2Config);

              if (copyResponse.ok) {
                await deleteR2Object(sourceKey, r2Config);
                
                const cleanMapUrl = `https://media.merian.app/${targetKey}`;
                migrated = true;
                totalMigrated++;
                return cleanMapUrl;
              } else {
                console.error(`S3 Copy Failed mapping ${sourceKey}: ${copyResponse.statusText}`);
                const brokenMapUrl = `https://media.merian.app/${sourceKey}`;
                return brokenMapUrl;
              }
            } else {
              return urlStr;
            }
          });

          const resolvedUrls = await Promise.all(urlPromises);

          if (migrated) {
            await supabaseAdmin
              .from("scans")
              .update({ image_storage_urls: resolvedUrls })
              .eq("id", scan.id);
          }
        }));
      }

      if (scans.length < pageSize) {
        hasMore = false;
      } else {
        start += pageSize;
      }
    }
    
    console.log(`S3 Background Migration Complete. Relocated ${totalMigrated} blobs from ${sourcePrefix} to ${targetPrefix} for ${userId}.`);
  } catch (e) {
    console.error(`Background S3 Migration (${sourcePrefix}->${targetPrefix}) aborted natively: `, e);
  }
}

serve(async (req: Request) => {
  try {
    const WEBHOOK_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
    const authHeader = req.headers.get("Authorization");

    if (!WEBHOOK_SECRET || authHeader !== `Bearer ${WEBHOOK_SECRET}`) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body = await req.json();
    const event = body.event;

    if (!event) {
      return jsonResponse({ error: "No event found" }, 400);
    }

    const eventType = event.type;
    const userId = event.app_user_id;

    if (!userId) {
      return jsonResponse({ error: "No app_user_id found" }, 400);
    }

    console.log(`Received Webhook: ${eventType} for User: ${userId}`);

    // Ensure user exists in our DB, upsert ghost if missing
    await supabaseAdmin
      .from("users")
      .upsert({ id: userId, subscription_tier: "free" }, { onConflict: "id", ignoreDuplicates: true });

    // Safely extract the native EdgeRuntime execution bounds
    const globalObj = globalThis as unknown as { EdgeRuntime?: { waitUntil: (p: Promise<void>) => void } };
    const runBackground = (task: Promise<void>) => {
      if (typeof globalObj.EdgeRuntime === "object" && typeof globalObj.EdgeRuntime.waitUntil === "function") {
        globalObj.EdgeRuntime.waitUntil(task);
      } else {
        task.catch(console.error);
      }
    };

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
      runBackground(migrateUserStorage(userId, "free", "pro"));
    } else if (["EXPIRATION"].includes(eventType)) {
      // Revert user tier strictly back to 'free'
      const { error: downgradeError } = await supabaseAdmin
        .from("users")
        .update({ subscription_tier: "free" })
        .eq("id", userId);

      if (downgradeError) {
        throw new Error(`Failed to downgrade user tier: ${downgradeError.message}`);
      }
      
      // Phase 2: Decoupled S3 Expiration Migration bridging payload natively over bounds
      runBackground(migrateUserStorage(userId, "pro", "free"));
    }

    return jsonResponse({ success: true }, 200);
  } catch (error: Error | unknown) {
    console.error("Webhook processing failed:", error);
    const msg = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: msg }, 500);
  }
});
