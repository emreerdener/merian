import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

serve(async (req: Request) => {
  try {
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

      // 2. Query the user's scans for objects that need migration from /free/
      const { data: scans, error: scansError } = await supabaseAdmin
        .from("scans")
        .select("id, image_storage_urls")
        .eq("user_id", userId);

      if (scansError) {
        throw new Error(`Failed to fetch scans: ${scansError.message}`);
      }

      const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID")!;
      const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY")!;

      const aws = new AwsClient({
        accessKeyId: R2_ACCESS_KEY_ID,
        secretAccessKey: R2_SECRET_ACCESS_KEY,
        service: "s3",
        region: "auto",
      });

      const scansList = scans || [];
      const CHUNK_SIZE = 25;

      for (let i = 0; i < scansList.length; i += CHUNK_SIZE) {
        const chunk = scansList.slice(i, i + CHUNK_SIZE);
        
        await Promise.allSettled(
          chunk.map(async (scan) => {
            const urls: string[] = scan.image_storage_urls || [];
            let updated = false;
            const newUrls: string[] = [];

            for (const url of urls) {
              if (url.includes(`/public_uploads/free/`)) {
                const urlObj = new URL(url);
                const sourcePath = urlObj.pathname; // format: /BUCKET/public_uploads/free/...
                const destPath = sourcePath.replace("/public_uploads/free/", "/public_uploads/pro/");
                const newUrlStr = urlObj.protocol + "//" + urlObj.host + destPath;

                // Step A: PUT Copy payload to Pro prefix
                const signedCopy = await aws.sign(newUrlStr, {
                  method: "PUT",
                  headers: {
                    "x-amz-copy-source": encodeURI(sourcePath),
                  },
                });
                const copyRes = await fetch(signedCopy);

                if (copyRes.ok) {
                  // Step B: DELETE original object from Free prefix
                  const signedDelete = await aws.sign(url, { method: "DELETE" });
                  await fetch(signedDelete);

                  newUrls.push(newUrlStr);
                  updated = true;
                } else {
                  console.error(`Failed to copy R2 object ${sourcePath} -> ${destPath}: ${copyRes.statusText}`);
                  newUrls.push(url); // Keep legacy URL if we natively failed to copy
                }
              } else {
                newUrls.push(url); // Unaffected payload
              }
            }

            // 3. Update the scan's storage URLs array
            if (updated) {
              await supabaseAdmin
                .from("scans")
                .update({ image_storage_urls: newUrls })
                .eq("id", scan.id);
            }
          })
        );
      }
    } else if (["CANCELLATION", "EXPIRATION"].includes(eventType)) {
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
