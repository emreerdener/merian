import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { getS3Client } from "../_shared/aws.ts";
import { decodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";
import { SafetyRating } from "https://esm.sh/@google/generative-ai@0.24.1";

export async function evaluateAndProcessPayload(
  userId: string,
  r2ObjectKeys: string[] | undefined,
  imageBase64s: string[] | undefined,
  geminiFinishReason: string | undefined,
  safetyRatings: SafetyRating[] | undefined,
  userTier: string,
): Promise<{ status: string; publicUrls?: string[] }> {
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

    // 3. Unsafe Flow Pipeline
    if (isUnsafe) {
      console.warn(
        `Unsafe media detected for user ${userId}. Engaging Unsafe Flow.`,
      );

      // Step A: Send DELETE request purging image explicitly from staging (if uploaded remotely)
      if ((!imageBase64s || imageBase64s.length === 0) && r2ObjectKeys && r2ObjectKeys.length > 0) {
          const deleteReqs = r2ObjectKeys.map(async (key) => {
              const stagingUrl = `${endpoint}/${R2_BUCKET_NAME}/${key}`;
              const deleteReq = new Request(stagingUrl, { method: "DELETE" });
              const signedDelete = await aws.sign(deleteReq);
              return fetch(signedDelete);
          });
          await Promise.allSettled(deleteReqs);
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
    const publicUrls: string[] = [];

    // Step A: Migrate source image securely into R2 explicit bounds natively
    if (imageBase64s && imageBase64s.length > 0) {
        let index = 0;
        for (const base64 of imageBase64s) {
            const fallbackUUID = crypto.randomUUID();
            const fileName = r2ObjectKeys?.[index]?.split("/").pop() || `${fallbackUUID}.jpg`;
            const publicUploadKey = `public_uploads/${tier}/${userId}/${fileName}`;
            const targetS3Url = `${endpoint}/${R2_BUCKET_NAME}/${publicUploadKey}`;
            
            // Direct conversion natively decoding the Base64 boundary String down into Uint8Array
            const arrayBuffer = decodeBase64(base64);
            const uploadReq = new Request(targetS3Url, {
                method: "PUT",
                headers: { "Content-Type": "image/jpeg" },
                body: arrayBuffer as unknown as BodyInit
            });
            const signedUpload = await aws.sign(uploadReq);
            const uploadRes = await fetch(signedUpload);
            if (!uploadRes.ok) {
                console.error(`Failed to upload direct Base64 buffer into R2. Pipeline stopped.`);
            } else {
                publicUrls.push(`https://media.merian.app/${publicUploadKey}`);
            }
            index++;
        }
    } else if (r2ObjectKeys && r2ObjectKeys.length > 0) {
        for (const r2Key of r2ObjectKeys) {
            const fileName = r2Key.split("/").pop();
            const publicUploadKey = `public_uploads/${tier}/${userId}/${fileName}`;
            const targetS3Url = `${endpoint}/${R2_BUCKET_NAME}/${publicUploadKey}`;
            const stagingUrl = `${endpoint}/${R2_BUCKET_NAME}/${r2Key}`;

            const copyReq = new Request(targetS3Url, {
              method: "PUT",
              headers: {
                "x-amz-copy-source": `/${R2_BUCKET_NAME}/${r2Key}`,
              },
            });

            const signedCopy = await aws.sign(copyReq);
            const copyRes = await fetch(signedCopy);

            if (copyRes.ok) {
              // Step B: Purge origin from staging payload block after valid internal transfer
              const originDeleteReq = new Request(stagingUrl, { method: "DELETE" });
              const signedOriginDelete = await aws.sign(originDeleteReq);
              await fetch(signedOriginDelete);
              
              publicUrls.push(`https://media.merian.app/${publicUploadKey}`);
            } else {
              console.error(`Failed to promote staging payload into R2. Pipeline stopped.`);
            }
        }
    }

    return { status: "PROMOTED", publicUrls: publicUrls };
  } catch (error) {
    console.error(`Moderation Pipeline Critical Failure:`, error);
    return { status: "ERROR" };
  }
}
