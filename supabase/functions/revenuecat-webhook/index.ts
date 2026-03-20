import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { getR2Config } from "../_shared/aws.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

async function migrateUserStorage(userId: string, sourcePrefix: string, targetPrefix: string) {
  try {
    const { s3Client, bucketName, endpoint } = getR2Config();

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

              const copyUrl = `${endpoint}/${bucketName}/${targetKey}`;
              const deleteUrl = `${endpoint}/${bucketName}/${sourceKey}`;

              const copyResponse = await s3Client.fetch(copyUrl, {
                method: "PUT",
                headers: {
                  "x-amz-copy-source": encodeURI(`/${bucketName}/${sourceKey}`)
                }
              });

              if (copyResponse.ok) {
                await s3Client.fetch(deleteUrl, { method: "DELETE" });
                
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
      // @ts-ignore: EdgeRuntime is a global context native to Supabase Edge execution
      EdgeRuntime.waitUntil(migrateUserStorage(userId, "free", "pro"));
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
      // @ts-ignore: EdgeRuntime is a global context native to Supabase Edge execution
      EdgeRuntime.waitUntil(migrateUserStorage(userId, "pro", "free"));
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
