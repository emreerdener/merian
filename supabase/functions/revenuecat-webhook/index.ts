import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";

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
      // Deferring bulk R2 bucket copying from /free/ to /pro/ physically into EdgeRuntime.waitUntil(promise) 
      // to guarantee webhook completes well within the 10-second Deno Edge limit and avoids 504 RevenueCat Retry loops.
      // @ts-ignore: EdgeRuntime is a global context native to Supabase Edge execution
      EdgeRuntime.waitUntil(
        (async () => {
          try {
            const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID")!;
            const R2_BUCKET_NAME = Deno.env.get("R2_BUCKET_NAME")!;
            const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID")!;
            const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY")!;

            const aws = new AwsClient({
              accessKeyId: R2_ACCESS_KEY_ID,
              secretAccessKey: R2_SECRET_ACCESS_KEY,
              service: "s3",
              region: "auto",
            });

            const endpoint = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;

            let totalMigrated = 0;
            let hasMore = true;
            let start = 0;
            const pageSize = 1000;

            while (hasMore) {
              // Explicitly map all existing free-tier data blobs off PostgreSQL natively utilizing pagination
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

              for (const scan of scans) {
                if (!scan.image_storage_urls || scan.image_storage_urls.length === 0) continue;

                let migrated = false;
                const newUrls: string[] = [];

                for (const urlStr of scan.image_storage_urls) {
                  if (urlStr.includes(`public_uploads/free/${userId}/`)) {
                    const parsedUrl = new URL(urlStr);
                    const fileName = parsedUrl.pathname.split("/").pop();

                    const sourceKey = `public_uploads/free/${userId}/${fileName}`;
                    const targetKey = `public_uploads/pro/${userId}/${fileName}`;

                    const copyUrl = `${endpoint}/${R2_BUCKET_NAME}/${targetKey}`;
                    const deleteUrl = `${endpoint}/${R2_BUCKET_NAME}/${sourceKey}`;

                    const copyResponse = await aws.fetch(copyUrl, {
                      method: "PUT",
                      headers: {
                        "x-amz-copy-source": `/${R2_BUCKET_NAME}/${sourceKey}`
                      }
                    });

                    if (copyResponse.ok) {
                      // Physically terminate the free-tier origin bounding
                      await aws.fetch(deleteUrl, { method: "DELETE" });
                      
                      // Strip any expired AWS signature query parameters natively protecting the new public Cloudflare route
                      const cleanMapUrl = `https://media.merian.app/${targetKey}`;
                      newUrls.push(cleanMapUrl);
                      migrated = true;
                      totalMigrated++;
                    } else {
                      console.error(`S3 Copy Failed mapping ${sourceKey}: ${copyResponse.statusText}`);
                      
                      // If the copy fails (e.g. 404, already deleted), strip the params from the active string to ensure the frontend doesn't hang on expired auth tokens
                      const brokenMapUrl = `https://media.merian.app/${sourceKey}`;
                      newUrls.push(brokenMapUrl);
                    }
                  } else {
                    newUrls.push(urlStr);
                  }
                }

                if (migrated) {
                  await supabaseAdmin
                    .from("scans")
                    .update({ image_storage_urls: newUrls })
                    .eq("id", scan.id);
                }
              }

              if (scans.length < pageSize) {
                hasMore = false;
              } else {
                start += pageSize;
              }
            }
            
            console.log(`S3 Background Migration Complete. Relocated ${totalMigrated} blobs physically to Pro architecture for ${userId}.`);
          } catch (e) {
            console.error("Background S3 Migration physically aborted natively: ", e);
          }
        })()
      );
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
