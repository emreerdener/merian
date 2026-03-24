import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { getR2Config, copyR2Object, deleteR2Object } from "../_shared/aws.ts";
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
    // 1. Evaluate Gemini safety ratings
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

    const r2Config = getR2Config();
    const { s3Client, bucketName, endpoint } = r2Config;
    const tier = userTier === "pro" ? "pro" : "free";

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // 2. Unsafe flow — purge staging image and escalate abuse strike
    if (isUnsafe) {
      console.warn(`Unsafe media detected for user ${userId}.`);

      if ((!imageBase64s || imageBase64s.length === 0) && r2ObjectKeys && r2ObjectKeys.length > 0) {
        await Promise.allSettled(r2ObjectKeys.map(key => deleteR2Object(key, r2Config)));
      }

      const { data: userData, error: fetchError } = await supabase
        .from("users")
        .select("abuse_strikes")
        .eq("id", userId)
        .single();

      if (fetchError && fetchError.code !== "PGRST116") {
        console.error("Failed to fetch user for safety escalation:", fetchError);
      }

      const currentStrikes = userData?.abuse_strikes ?? 0;
      const updatedStrikes = currentStrikes + 1;
      const isShadowbanned = updatedStrikes >= 3;

      const { error: updateError } = await supabase
        .from("users")
        .update({ abuse_strikes: updatedStrikes, is_shadowbanned: isShadowbanned })
        .eq("id", userId);

      if (updateError) {
        console.error("Failed to update abuse strikes:", updateError);
      }

      return { status: isShadowbanned ? "SHADOWBANNED" : "DELETED_WARNING" };
    }

    // 3. Safe flow — promote image to public storage
    console.log(`Media safe for user ${userId}. Engaging safe flow pipeline.`);
    const publicUrls: string[] = [];

    if (imageBase64s && imageBase64s.length > 0) {
      let index = 0;
      for (const base64 of imageBase64s) {
        const fallbackUUID = crypto.randomUUID();
        const fileName = r2ObjectKeys?.[index]?.split("/").pop() || `${fallbackUUID}.jpg`;
        const publicUploadKey = `public_uploads/${tier}/${userId}/${fileName}`;
        const targetS3Url = `${endpoint}/${bucketName}/${publicUploadKey}`;

        const arrayBuffer = decodeBase64(base64);
        const uploadReq = new Request(targetS3Url, {
          method: "PUT",
          headers: { "Content-Type": "image/jpeg" },
          body: arrayBuffer as unknown as BodyInit
        });
        const signedUpload = await s3Client.sign(uploadReq);
        const uploadRes = await fetch(signedUpload);
        if (!uploadRes.ok) {
          console.error(`Failed to upload base64 image to R2.`);
        } else {
          publicUrls.push(`https://media.merian.app/${publicUploadKey}`);
        }
        index++;
      }
    } else if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      for (const r2Key of r2ObjectKeys) {
        const fileName = r2Key.split("/").pop();
        const publicUploadKey = `public_uploads/${tier}/${userId}/${fileName}`;

        const copyRes = await copyR2Object(r2Key, publicUploadKey, r2Config);

        if (copyRes.ok) {
          await deleteR2Object(r2Key, r2Config);
          publicUrls.push(`https://media.merian.app/${publicUploadKey}`);
        } else {
          console.error(`Failed to promote staging image to public storage.`);
        }
      }
    }

    return { status: "PROMOTED", publicUrls };
  } catch (error) {
    console.error("Moderation pipeline error:", error);
    return { status: "ERROR" };
  }
}
