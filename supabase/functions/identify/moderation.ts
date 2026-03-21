import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { getS3Client } from "../_shared/aws.ts";
import { decodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

export async function evaluateAndProcessPayload(
  userId: string,
  r2ObjectKey: string,
  imageBase64: string | undefined,
  geminiFinishReason: string | undefined,
  // deno-lint-ignore no-explicit-any
  safetyRatings: any[] | undefined,
  userTier: string,
): Promise<{ status: string; publicUrl?: string }> {
  try {
    // 1. Evaluate Gemini Safety Ratings and Finish Reason
    let isUnsafe = false;

    if (geminiFinishReason === "SAFETY") {
      isUnsafe = true;
    } else if (safetyRatings && Array.isArray(safetyRatings)) {
      for (const rating of safetyRatings) {
        if (rating.probability === "MEDIUM" || rating.probability === "HIGH") {
          isUnsafe = true;
          break;
        }
      }
    }

    // 2. Initialize Core Clients
    const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID")!;
    const R2_BUCKET_NAME = Deno.env.get("R2_BUCKET_NAME")!;

    const aws = getS3Client();

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    // Service role key is required to patch user abuse_strikes reliably
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const tier = userTier === "pro" ? "pro" : "free";

    const endpoint = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
    const fileName = r2ObjectKey.split("/").pop();
    const publicUploadKey = `public_uploads/${tier}/${userId}/${fileName}`;

    const stagingUrl = `${endpoint}/${R2_BUCKET_NAME}/${r2ObjectKey}`;
    const targetS3Url = `${endpoint}/${R2_BUCKET_NAME}/${publicUploadKey}`;
    
    // The public viewer URL to save in PostgreSQL
    const publicR2DevUrl = `https://media.merian.app/${publicUploadKey}`;

    // 3. Unsafe Flow Pipeline
    if (isUnsafe) {
      console.warn(
        `Unsafe media detected for user ${userId}. Engaging Unsafe Flow.`,
      );

      // Step A: Send DELETE request purging image explicitly from staging (if uploaded remotely)
      if (!imageBase64) {
          const deleteReq = new Request(stagingUrl, { method: "DELETE" });
          const signedDelete = await aws.sign(deleteReq);
          await fetch(signedDelete);
      }

      // Step B: Fetch and increment abuse strikes in Supabase
      const { data: userData, error: fetchError } = await supabase
        .from("users")
        .select("abuse_strikes")
        .eq("id", userId)
        .single();

      if (fetchError && fetchError.code !== "PGRST116") {
        console.error(
          `Failed to fetch user profiles for safety escalation. Error:`,
          fetchError,
        );
      }

      const currentStrikes = userData?.abuse_strikes ?? 0;
      const updatedStrikes = currentStrikes + 1;
      const isShadowbanned = updatedStrikes >= 3;

      // Step C: Update penalty counters
      const { error: updateError } = await supabase
        .from("users")
        .update({
          abuse_strikes: updatedStrikes,
          is_shadowbanned: isShadowbanned,
        })
        .eq("id", userId);

      if (updateError) {
        console.error(`Failed to update user bounds. Error:`, updateError);
      }

      return { status: isShadowbanned ? "SHADOWBANNED" : "DELETED_WARNING" };
    }

    // 4. Safe Flow Pipeline
    console.log(`Media marked safe. Engaing Safe Flow Pipeline.`);

    // Step A: Migrate source image securely into R2 explicit bounds natively
    if (imageBase64) {
        // Direct conversion natively decoding the Base64 boundary String down into Uint8Array
        const arrayBuffer = decodeBase64(imageBase64);
        
        const uploadReq = new Request(targetS3Url, {
            method: "PUT",
            headers: {
                "Content-Type": "image/jpeg"
            },
            body: arrayBuffer as unknown as BodyInit
        });
        const signedUpload = await aws.sign(uploadReq);
        const uploadRes = await fetch(signedUpload);
        if (!uploadRes.ok) {
            console.error(`Failed to upload direct Base64 buffer into R2. Pipeline stopped.`);
        }
    } else {
        const copyReq = new Request(targetS3Url, {
          method: "PUT",
          headers: {
            "x-amz-copy-source": `/${R2_BUCKET_NAME}/${r2ObjectKey}`,
          },
        });

        const signedCopy = await aws.sign(copyReq);
        const copyRes = await fetch(signedCopy);

        if (copyRes.ok) {
          // Step B: Purge origin from staging payload block after valid internal transfer
          const originDeleteReq = new Request(stagingUrl, { method: "DELETE" });
          const signedOriginDelete = await aws.sign(originDeleteReq);
          await fetch(signedOriginDelete);
        } else {
          console.error(`Failed to promote staging payload into R2. Pipeline stopped.`);
        }
    }

    return { status: "PROMOTED", publicUrl: publicR2DevUrl };
  } catch (error) {
    console.error(`Moderation Pipeline Critical Failure:`, error);
    return { status: "ERROR" };
  }
}
